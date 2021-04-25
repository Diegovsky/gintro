const std = @import("std");

pub fn build(b: *std.build.Builder) !void {
    const mode = b.standardReleaseOptions();

    const lib = b.addStaticLibrary("gintro", "src/lib.zig");
    lib.linkSystemLibrary("gobject-introspection-1.0");
    // lib.linkSystemLibraryName("gobject-introspection-1.0");
    lib.linkLibC();
    lib.setBuildMode(mode);
    lib.install();

    const exe = b.addExecutable("main", "src/main.zig");
    // Workaround until I understand Zig's build system :/
    {
        exe.addPackage(.{ .name = "gintro", .path = lib.root_src.?.path });
        try exe.link_objects.appendSlice(lib.link_objects.items);
        try exe.include_dirs.appendSlice(lib.include_dirs.items);
        try exe.lib_paths.appendSlice(lib.lib_paths.items);
    }
    exe.linkLibC();
    exe.setBuildMode(.Debug);
    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // for (exe.include_dirs.items) |dir| {
    //     std.debug.print("Include paths: {s}\n", .{dir.RawPath});
    // }
    // for (exe.link_objects.items) |dir| {
    //     switch(dir) {
    //         .SystemLib,
    //         .StaticPath => |p| {
    //             std.debug.print("Libs: {s}\n", .{p});
    //         },
    //         else => {},
    //     }
    // }

    var main_tests = b.addTest("src/main.zig");
    main_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);
}
