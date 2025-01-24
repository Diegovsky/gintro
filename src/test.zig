const std = @import("std");
const gintro = @import("lib.zig");
const expect = std.testing.expect;

const GI = struct {
    repo: gintro.Repository,
    gi: gintro.Namespace,

    fn getAnyOf(gi: *@This(), comptime T: type) ?T {
        var iterator = gi.repo.getInfoIterator(&gi.gi);
        while (iterator.next()) |info| {
            if (info.tryCast(T)) |val| {
                return val;
            }
            info.unref();
        }
        return null;
    }
};

fn getRepo() GI {
    var repo = gintro.Repository.default();
    var gi = gintro.Namespace{ .name = "GIRepository", .version = "2.0" };
    _ = repo.require(&gi, .LoadLazy) catch unreachable;
    return .{ .repo = repo, .gi = gi };
}

test "BaseInfo Casting" {
    var gi = getRepo();
    const si = gi.getAnyOf(gintro.StructInfo) orelse unreachable;
    const bi = si.tryCast(gintro.BaseInfo) orelse unreachable;
    try expect(bi.tryCast(gintro.StructInfo) != null);
    try expect(bi.tryCast(gintro.FunctionInfo) == null);
}

test "Function Casting" {
    var gi = getRepo();
    const si = gi.getAnyOf(gintro.FunctionInfo) orelse unreachable;
    const bi = si.tryCast(gintro.CallableInfo) orelse unreachable;
    try expect(bi.tryCast(gintro.BaseInfo) != null);
}
