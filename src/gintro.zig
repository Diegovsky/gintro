const std = @import("std");
const gintro = @import("lib.zig");
const zig = @import("zig.zig");

const print = std.debug.print;


pub fn main() !void {
    var repo = gintro.Repository.default();
    var gi = gintro.Namespace{ .name = "GIRepository", .version = "2.0" };
    //var gi = gintro.Namespace{ .name = "Gtk", .version = "4.0" };
    _ = try repo.require(&gi, .LoadLazy);
    var iterator = repo.getInfoIterator(&gi);
    while (iterator.next()) |info_| {
        var info = info_;
        print("{?s}\n", .{info.getName()});
        defer info.unref();
        if (info.getType() == gintro.TypeInfo.Struct) {
            var attriter = info.getIterator();
            var fields = std.ArrayList(zig.FieldInfo).init(std.heap.c_allocator);
            while(attriter.next()) |attr| {
                std.debug.print("{s} {s}\n", .{attr[0], attr[1]});
                try fields.append(zig.FieldInfo {.name = attr[0].copy().slice(), .ty = attr[1].copy().slice()});
            }
            std.debug.print("{?s}\n", .{info.getName()});
            std.debug.print("items: {any}\n", .{fields.items});
        }
    }
}

