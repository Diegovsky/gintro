const std = @import("std");
const gintro = @import("lib.zig");
const zig = @import("zig.zig");

const print = std.debug.print;


pub fn main() !void {
    var repo = gintro.Repository.default();
    //var gi = gintro.Namespace{ .name = "GIRepository", .version = "2.0" };
    var gi = gintro.Namespace{ .name = "Gtk", .version = "4.0" };
    _ = try repo.require(&gi, .LoadLazy);
    var iterator = repo.getInfoIterator(&gi);
    var stdout = std.io.getStdOut();
    while (iterator.next()) |info| {
        defer info.unref();
        if(info.downcast(gintro.StructInfo)) |sinfo| {
            var zinfo = zig.StructInfo.new(sinfo);
            defer zinfo.deinit();
            try zinfo.toZig(stdout);
        }
    }
}

