const std = @import("std");

pub const FieldInfo = struct {
    name: []const u8,
    ty: []const u8,

    pub fn format(value: @This(), comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) std.os.WriteError!void {
        return writer.print("<{s}: {s}>", .{ value.name, value.ty });
    }
};

pub const StructInfo = struct {
    name: []const u8,
    fields: []const FieldInfo,

    pub fn format(sinfo: StructInfo, comptime args: []const u8, _: std.fmt.FormatOptions, writer: anytype) std.os.WriteError!void {
        const pretty = if(args.len > 0) args[0] == 'p' else false;
        try writer.print("pub const {s} = struct {{", .{sinfo.name});
        // Ease code reuse.
        const prettier = struct {
            writer: @TypeOf(writer),

            fn pretty_write(self: @This(), str: []const u8) !void {
                if(pretty) {
                    _ = try self.writer.write(str);
                }
            }
        } {.writer = writer};
        try prettier.pretty_write("\n");
        for (sinfo.fields) |finfo| {
            try prettier.pretty_write(" "**2);
            try writer.print("{},", .{finfo});
        }
        try prettier.pretty_write("\n");
        _ = try writer.write("};");
    }
};
