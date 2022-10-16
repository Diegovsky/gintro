const std = @import("std");
const gintro = @import("lib.zig");

const allocator = std.heap.c_allocator;

pub const FieldInfo = struct {
    name: []const u8,
    ty: []const u8,

    pub fn toZig(value: @This(), writer: anytype) std.os.WriteError!void {
        return writer.print("{s}: {s}", .{ value.name, value.ty });
    }

};

pub const StructInfo = struct {
    name: []const u8,
    fields: []const FieldInfo,

    pub fn toZig(value: @This(), writer: anytype) std.os.WriteError!void {
        try writer.print("pub const {s} = struct {{", .{value.name});
        for (value.fields) |finfo, i| {
            try finfo.toZig(writer);
            if(i != value.fields.len) {
                try writer.writeAll(",\n");
            }
        }
        try writer.writeAll("}}\n");
    }

    pub fn new(info: gintro.StructInfo) @This() {
        var list = std.ArrayList(FieldInfo).init(allocator);
        var it = info.getFieldsIterator();
        while(it.next()) |field| {
            list.append(.FieldInfo {.name = field.upcast().getName().?.slice()}) orelse unreachable;
        }
        return . {
            .name = info.upcast().getName().?.slice(),
            .ty = list.toOwnedSlice(),
        };
    }

    pub fn deinit(self: @This()) void {
        allocator.free(self.fields);
    }
};
