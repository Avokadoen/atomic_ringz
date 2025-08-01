const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const atomic_rings = b.addModule("root", .{
        .root_source_file = b.path("src/root.zig"),
        .imports = &.{},
        .target = target,
        .optimize = optimize,
    });

    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "atomic_ringz",
        .root_module = atomic_rings,
    });

    b.installArtifact(lib);

    const lib_unit_tests = b.addTest(.{
        .root_module = atomic_rings,
    });
    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
}
