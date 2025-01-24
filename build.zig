const std = @import("std");

pub fn build(b: *std.build.Builder) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addStaticLibrary(.{ .name = "gintro", .root_source_file = .{ .path = "src/lib.zig" }, .target = target, .optimize = optimize });
    lib.linkLibC();
    lib.linkSystemLibrary("gobject-introspection-1.0");

    const exe = b.addExecutable(.{
        .name = "gintro",
        .root_source_file = .{ .path = "src/gintro.zig" },
        .target = target,
        .optimize = optimize,
    });
    exe.linkLibrary(lib);
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    var main_tests = b.addTest(.{ .root_source_file = .{ .path = "src/test.zig" }, .optimize = optimize, .target = target });
    main_tests.linkLibrary(lib);

    const run_test = b.addRunArtifact(main_tests);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_test.step);
}
