const std = @import("std");

pub const Block = struct {
    pub const empty = Block{
        .version = .init(0),
        .data_ize = .init(0),
        .data = undefined,
    };

    version: std.atomic.Value(u64),
    data_size: std.atomic.Value(u8),
    data: [128]u8,
};

const Header = struct {
    pub const empty = Header{
        .block_counter = .init(0),
    };

    block_counter: std.atomic.Value(u32),
};

pub const SPMCQueue = struct {
    header: Header,
    blocks: []Block,

    pub fn init(blocks_buffer: []Block) SPMCQueue {
        return SPMCQueue{
            .header = .empty,
            .blocks = blocks_buffer,
        };
    }

    pub fn write(self: *SPMCQueue, msg: []const u8) void {
        // the next block index to write to
        const block_index = self.header.block_counter.fetchAdd(1, .acquire) % self.blocks.len;
        var block = &self.blocks[block_index];

        var current_version = block.version.load(.acquire) + 1;
        // If the block has been written to before, it has an odd version
        // we need to make its version even before writing begins to indicate that writing is in progress
        if (@mod(block.version.load(.acquire), 2) == 1) {
            // make the version even
            block.version.store(current_version, .release);
            // store the newVersion used for after the writing is done
            current_version += 1;
        }
        // store the size
        block.data_size.store(@intCast(msg.len), .release);
        // store the msg
        @memcpy(block.data[0..msg.len], msg);

        // store the new odd version
        block.version.store(current_version, .release);
    }

    pub fn read(self: *SPMCQueue, block_index: u64, dest_buffer: *[128]u8) ?[]const u8 {
        var block = &self.blocks[block_index];
        const version = block.version.load(.acquire);
        if (@mod(version, 2) == 1) {
            const size = block.data_size.load(.acquire);
            // Perform the read
            @memcpy(dest_buffer[0..size], block.data[0..size]);
            // Indicate that a read has occurred by adding a 2 to the version
            // However do not block subsequent reads
            block.version.store(version + 2, .release);
            return dest_buffer[0..size];
        }
        return null;
    }
};

pub export fn add(a: i32, b: i32) i32 {
    return a + b;
}

const testing = std.testing;
test "contention is fine" {
    const write = struct {
        pub fn func(is_running: *std.atomic.Value(bool), queue: *SPMCQueue) void {
            var id: u64 = 0;
            var msg_buf: [128]u8 = undefined;
            while (is_running.load(.acquire)) {
                const msg = std.fmt.bufPrint(&msg_buf, "Message {d}", .{id}) catch @panic("oh no");
                queue.write(msg);
                id += 1;
            }
        }
    }.func;

    const read = struct {
        pub fn func(is_running: *std.atomic.Value(bool), idx: usize, queue: *SPMCQueue, msg_count: *std.atomic.Value(u64)) void {
            var block_index: u32 = 0;
            var dest_buffer: [128]u8 = undefined;
            while (is_running.load(.acquire)) {
                if (queue.read(block_index, &dest_buffer)) |msg| {
                    _ = idx;
                    _ = msg;
                    _ = msg_count.fetchAdd(1, .acquire);

                    block_index += 1;
                    if (block_index >= queue.blocks.len) block_index = 0;
                }
            }
        }
    }.func;

    var blocks: [1024]Block = undefined;
    var queue = SPMCQueue.init(&blocks);
    var is_running = std.atomic.Value(bool).init(true);

    const writer_t = try std.Thread.spawn(.{}, write, .{ &is_running, &queue });

    var msg_count = std.atomic.Value(u64).init(0);
    var reader_ts: [20]std.Thread = undefined;
    for (&reader_ts, 0..) |*thread, thread_idx| {
        thread.* = try std.Thread.spawn(.{}, read, .{ &is_running, thread_idx, &queue, &msg_count });
    }

    std.Thread.sleep(std.time.ns_per_s * 5);
    is_running.store(false, .monotonic);

    writer_t.join();
    for (reader_ts) |thread| {
        thread.join();
    }

    std.debug.print("\nmsg_count: {d}\n", .{msg_count.load(.acquire)});
}
