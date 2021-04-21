const gintro = @import("lib.zig");

pub fn main() !void {
    var repo = gintro.Repository.default();
    var gi = .{ .name = "GIRepository", .version = "2.0" };
    _ = try repo.require(&gi, .LoadLazy);
    var iterator = repo.getInfoIterator(&gi);
    while (iterator.next()) |info| {
        std.debug.print("Name: {s}\n", .{C.g_base_info_get_name(info)});
    }
}
