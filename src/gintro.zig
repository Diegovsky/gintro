const std = @import("std");
const gintro = @import("lib.zig");
const zig = @import("zig.zig");

const print = std.debug.print;

pub fn main() !void {
    var repo = gintro.Repository.default();
    var gi = gintro.Namespace{ .name = "GIRepository", .version = "2.0" };
    // var gi = gintro.Namespace{ .name = "Gtk", .version = "4.0" };
    _ = try repo.require(&gi, .LoadLazy);
    var iterator = repo.getInfoIterator(&gi);
    // var stdout = std.io.getStdOut();
    var stdout = try std.fs.createFileAbsolute("/tmp/pog.txt", .{ .truncate = true });
    std.debug.print("Pog \n", .{});
    while (iterator.next()) |info| {
        defer info.unref();
        // std.debug.print("Pog: {?s}\n", .{info.getName()});
        if (info.tryCast(gintro.StructInfo)) |sinfo| {
            // std.debug.print("Struct: {?s}\n", .{sinfo.super().getName()});
            var zinfo = zig.StructInfo.new(sinfo);
            defer zinfo.deinit();
            try zinfo.toZig(stdout.writer());
        }
    }
}
