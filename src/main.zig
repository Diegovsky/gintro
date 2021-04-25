const std = @import("std");
const gintro = @import("gintro");

pub fn main() !void {
    var repo = gintro.Repository.default();
    var gi = gintro.Namespace{ .name = "GIRepository", .version = "2.0" };
    _ = try repo.require(&gi, .LoadLazy);
    var iterator = repo.getInfoIterator(&gi);
    while (iterator.next()) |info| {
        std.debug.print("Name: {s}\n", .{info.getName().?.raw});
    }
}
