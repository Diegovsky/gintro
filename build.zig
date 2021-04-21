const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    const mode = b.standardReleaseOptions();

    const lib = b.addStaticLibrary("gintro", "src/lib.zig");
    lib.linkSystemLibrary("gobject-introspection-1.0");
    lib.linkLibC();
    lib.setBuildMode(mode);
    lib.install();

    const exe = b.addExecutable("main", "src/main.zig");
    exe.linkLibrary(lib);
    exe.setBuildMode(.Debug);
    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    for (lib.include_dirs.items) |dir| {
        std.debug.print("Include paths: {s}\n", .{dir.RawPath});
    }

    var main_tests = b.addTest("src/main.zig");
    main_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);
}
