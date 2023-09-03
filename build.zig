const std = @import("std");

pub fn build(b: *std.build) void {
    // Standard optimize option allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const btreemap_module = b.createModule(.{ //
        .source_file = .{ .path = "src/btreemap.zig" },
    });

    const main_tests = b.addTest(.{ //
        .name = "zig btreemap tests",
        .root_source_file = .{ .path = "src/btreemap.zig" },
        .target = target,
        .optimize = optimize,
    });
    main_tests.addModule("btreemap", btreemap_module);
    const run_main_tests = b.addRunArtifact(main_tests);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_main_tests.step);
}
