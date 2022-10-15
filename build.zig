const std = @import("std");

pub fn build(b: *std.build.Builder) !void {
    const mode = b.standardReleaseOptions();
    const target = b.standardTargetOptions(.{});

    const lib = b.addStaticLibrary("gintro", "src/lib.zig");
    lib.linkLibC();
    lib.linkSystemLibrary("gobject-introspection-1.0");

    const exe = b.addExecutable("gintro", "src/gintro.zig");
    exe.setTarget(target);
    exe.linkLibrary(lib);
    exe.setBuildMode(mode);
    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    var main_tests = b.addTest("src/gintro.zig");
    main_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);
}
