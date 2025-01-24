const std = @import("std");
const gintro = @import("lib.zig");

const StringMap = std.StringHashMap([]const u8);

fn Iter(comptime Item: type) type {
    return struct {
        pub fn assert(iterator: anytype) void {
            const Iterator = @TypeOf(iterator);
            const functions = .{ .next = Item };
            inline for (@typeInfo(@TypeOf(functions)).Struct.decls) |name| {
                if (!@hasDecl(Iterator, name)) {
                    @compileError(std.fmt.allocPrint("Type \"{s}\" is missing function `{s}`", .{ Iterator, name }));
                }
                const actual_return_type = @typeInfo(@field(Iterator, name)).Fn.return_type;
                const expected_return_type = @field(functions, name);
                if (actual_return_type != expected_return_type) {
                    @compileError(std.fmt.allocPrint("Function `{s}.{s}` expected to return `{s}`, but returns `{s}`", .{ Iterator, name, expected_return_type, actual_return_type }));
                }
            }
        }
    };
}

fn escape_name(name: []const u8, allocator: std.mem.Allocator) ![]const u8 {
    var escname = try allocator.alloc(u8, name.len + 1);
    std.mem.copy(u8, escname, name);
    escname[escname.len - 1] = '_';
    return escname;
}

const ItemSet = struct {
    storage: Storage,

    const Storage = std.StringArrayHashMap(void);

    pub fn init(allocator: std.mem.Allocator) ItemSet {
        return .{ .storage = Storage.init(allocator) };
    }

    pub fn contains(self: *const ItemSet, name: []const u8) bool {
        return self.storage.contains(name);
    }

    pub fn add(self: *ItemSet, name: []const u8) !void {
        try self.storage.put(name, {});
    }

    pub fn remove(self: *ItemSet, name: []const u8) !void {
        try self.storage.remove(name);
    }
};
const MissingTypesMap = std.AutoArrayHashMap(gintro.TypeLib, ItemSet);

pub fn ZigEmmiter(comptime Writer: type) type {
    return struct {
        writer: Writer,
        current_module: gintro.TypeLib = undefined,
        allocator: std.heap.ArenaAllocator,
        alloc: std.mem.Allocator = undefined,
        indent_level: u8 = 0,
        c_module_name: []const u8 = "C",
        tab_stop: u8 = 4,
        rename_table: StringMap,
        missing_types: MissingTypesMap,

        const Self = @This();

        fn deinit(self: *Self) void {
            self.allocator.deinit();
        }

        fn fmt_indent(self: *Self) !void {
            for (0..self.indent_level) |_| {
                _ = try self.write(" ");
            }
        }

        fn indent(self: *Self) void {
            self.indent_level += self.tab_stop;
        }

        fn unindent(self: *Self) void {
            self.indent_level -= self.tab_stop;
        }

        fn format(self: *Self, comptime fmt: []const u8, params: anytype) Writer.Error!void {
            try self.writer.print(fmt, params);
        }

        fn print(self: *Self, comptime fmt: []const u8, params: anytype) Writer.Error!void {
            try self.fmt_indent();
            try self.format(fmt, params);
        }

        fn println(self: *Self, comptime fmt: []const u8, params: anytype) Writer.Error!void {
            try self.print(fmt ++ "\n", params);
        }

        fn write(self: *Self, txt: []const u8) Writer.Error!void {
            _ = try self.writer.writeAll(txt);
        }

        fn writeln(self: *Self, txt: []const u8) Writer.Error!void {
            try self.write(txt);
            try self.write("\n");
        }

        fn type_info_to_zig(self: *Self, ty: gintro.TypeInfo) (Writer.Error || error{OutOfMemory})!void {
            const should_ref = switch (ty.getTag()) {
                .UTF8, .Array => false,
                .Void => false,
                else => true,
            };
            if (ty.isPointer() and should_ref) {
                try self.write("*");
            }
            switch (ty.getTag()) {
                .Boolean => try self.write("bool"),
                .Int8 => try self.write("i8"),
                .UInt8 => try self.write("u8"),
                .Int16 => try self.write("i16"),
                .UInt16 => try self.write("u16"),
                .Int32 => try self.write("i32"),
                .Unichar, .UInt32 => try self.write("u32"),
                .Int64 => try self.write("i64"),
                .UInt64 => try self.write("u64"),
                .Float => try self.write("f32"),
                .Double => try self.write("f64"),
                .GType => try self.write("glib.Type"),
                .UTF8 => try self.write("[*:0]const u8"),
                .Filename => try self.write("[*:0]const u8"),
                .Void => if (!ty.isPointer()) {
                    try self.write("void");
                } else {
                    try self.write("*anyopaque");
                },
                .Array => {
                    var item_type = ty.getParamType(0).?;
                    defer item_type.unref();
                    if (ty.getArrayFixedSize()) |size| {
                        try self.format("[{d}]", .{size});
                    } else {
                        try self.write("[]");
                    }
                    try self.type_info_to_zig(item_type);
                },
                .Interface => {
                    var interface = ty.getInterface().?;
                    defer interface.unref();
                    if (interface.getTypeLib().raw != self.current_module.raw) {
                        const tlib = interface.getTypeLib();
                        var missings = try self.missing_types.getOrPut(tlib);
                        if (!missings.found_existing) {
                            missings.value_ptr.* = ItemSet.init(self.alloc);
                        }
                        try missings.value_ptr.add(interface.getName().?);
                        try self.format("{s}.", .{interface.getTypeLib().getNamespace()});
                    }
                    if (interface.tryCast(gintro.CallbackInfo)) |callback| {
                        try self.callback_to_zig(callback);
                    } else {
                        try self.write(interface.getName().?);
                    }
                },
                .GError => try self.write("glib.Error"),
                .GList, .GSList => {
                    const tname = switch (ty.getTag()) {
                        .GList => "List",
                        .GSList => "SList",
                        else => unreachable,
                    };
                    try self.format("{s}.{s}", .{ self.c_module_name, tname });
                    if (ty.getParamType(0)) |item_type| {
                        defer item_type.unref();
                        if (item_type.getTag() != .Void) {
                            try self.write("(");
                            try self.type_info_to_zig(item_type);
                            try self.write(")");
                        }
                    }
                },
                .GHashTable => {
                    try self.format("{s}.HashTable", .{self.c_module_name});
                    if (ty.getParamType(0)) |key_type| {
                        defer key_type.unref();
                        if (key_type.getTag() != .Void) {
                            try self.write("(");
                            try self.type_info_to_zig(key_type);
                            try self.write(", ");
                            try self.type_info_to_zig(ty.getParamType(1).?);
                            try self.write(")");
                        }
                    }
                },
            }
        }

        fn emit_prelude(self: *Self, c_lib_names: []const []const u8) !void {
            const s = "const {s} = @cImport(";
            try self.println(s, .{self.c_module_name});
            const indent_space: u8 = @intCast(s.len - 3 + self.c_module_name.len);
            self.indent_level += indent_space;
            // C Imports
            for (c_lib_names) |c_lib_name| {
                try self.println("@cInclude(\"{s}\"),", .{c_lib_name});
            }
            try self.println(");\n", .{});
            self.indent_level -= indent_space;
        }

        fn get_name(self: *Self, name: []const u8) []const u8 {
            if (self.rename_table.get(name)) |new_name| {
                return new_name;
            }
            return name;
        }

        fn callback_to_zig(self: *Self, cinfo: gintro.CallbackInfo) !void {
            try self.write("fn (");
            var a = cinfo.getArgsIterator();
            while (a.next()) |arg| {
                defer arg.unref();
                try self.arg_to_zig(arg);
                if (a.i < a.len) {
                    try self.write(", ");
                }
            }
            try self.write(") ");
            if (cinfo.mayReturnNull()) {
                try self.write("?");
            }
            try self.type_info_to_zig(cinfo.getReturnType());
        }

        fn arg_to_zig(self: *Self, arg: gintro.ArgInfo) !void {
            try self.format("{s}", .{self.get_name(arg.getName().?)});
            try self.write(": ");
            if (arg.isOptional()) {
                try self.write("?");
            }
            const ty = arg.getType();
            defer ty.unref();
            if (arg.getDirection() == .Out) {
                try self.write("*");
            }
            try self.type_info_to_zig(ty);
        }

        fn type_tag_to_zig(self: *Self, type_tag: gintro.TypeTag) []const u8 {
            _ = self;
            return switch (type_tag) {
                .Int8 => "i8",
                .UInt8 => "u8",
                .Int16 => "i16",
                .UInt16 => "u16",
                .Int32 => "i32",
                .Unichar, .UInt32 => "u32",
                .Int64 => "i64",
                .UInt64 => "u64",
                .Float => "f32",
                .Double => "f64",
                else => unreachable,
            };
        }

        fn field_to_zig(self: *Self, field: gintro.FieldInfo) !void {
            if (field.getFlags().isReadable()) {
                var ftype = field.getType();
                defer ftype.unref();
                try self.println("// tag: {s}", .{@tagName(ftype.getTag())});
                try self.print("{s}: ", .{self.get_name(field.getName().?)});
                try self.type_info_to_zig(ftype);
            }
        }

        fn method_to_zig(self: *Self, this_type: ?[]const u8, method: gintro.FunctionInfo) !void {
            const fname = self.get_name(method.getName().?);
            try self.rename_table.put(fname, try escape_name(fname, self.alloc));
            defer {
                const item = self.rename_table.fetchRemove(fname).?;
                self.alloc.free(item.value);
            }
            try self.print("pub fn {s}(", .{fname});
            if (this_type) |t| {
                try self.format("self: {s}, ", .{t});
            }
            var a = method.getArgsIterator();
            var arg_names = try std.ArrayList([]const u8).initCapacity(self.alloc, @intCast(a.len + 1));
            if (this_type) |_| {
                arg_names.appendAssumeCapacity(try self.alloc.dupe(u8, "self"));
            }
            while (a.next()) |arg| {
                defer arg.unref();
                try self.arg_to_zig(arg);
                if (a.i < a.len) {
                    try self.write(", ");
                }
                arg_names.appendAssumeCapacity(try self.alloc.dupe(u8, self.get_name(arg.getName().?)));
            }
            try self.write(") ");
            if (method.mayReturnNull()) {
                try self.write("?");
            }
            try self.type_info_to_zig(method.getReturnType());
            try self.writeln(" {");
            self.indent();
            {
                defer self.unindent();
                const args = try std.mem.join(self.alloc, ", ", arg_names.items);
                defer self.alloc.free(args);
                try self.println("return {s}.{s}({s});", .{ self.c_module_name, method.getSymbol(), args });
            }
            try self.fmt_indent();
            try self.writeln("}");
        }

        pub fn fields_to_zig(self: *Self, field_iterator: anytype) !void {
            Iter(gintro.FieldInfo).assert(field_iterator);
            var iter = field_iterator;
            while (iter.next()) |field| {
                defer field.unref();
                try self.field_to_zig(field);
                try self.write(",\n");
            }
        }

        pub fn methods_to_zig(self: *Self, this_type: []const u8, method_iterator: anytype) !void {
            Iter(gintro.FunctionInfo).assert(method_iterator);
            var iter = method_iterator;
            while (iter.next()) |method| {
                defer method.unref();
                try self.method_to_zig(this_type, method);
            }
        }

        pub fn constant_to_zig(self: *Self, constant: gintro.ConstantInfo) !void {
            try self.print("pub extern const {s}: ", .{self.get_name(constant.getName().?)});
            const ty = constant.getType();
            defer ty.unref();
            try self.type_info_to_zig(ty);
            try self.write(";\n");
        }

        pub fn attrs_to_zig(self: *Self, attr_iterator: anytype) !void {
            Iter([2][]const u8).assert(attr_iterator);
            var iter = attr_iterator;
            while (iter.next()) |attr| {
                try self.println("// Attr: {s}={s}", .{ attr[0], attr[1] });
            }
        }

        pub fn struct_to_zig(self: *Self, sinfo: gintro.StructInfo) !void {
            if (sinfo.getTypeName()) |tname| {
                try self.println("// GObject name: {s}", .{tname});
            }
            try self.println("// Struct", .{});
            try self.println("pub const {s} = extern struct {{", .{sinfo.getName().?});
            self.indent();
            {
                defer self.unindent();

                // Attrs
                try self.attrs_to_zig(sinfo.getAttributeIterator());

                // fields
                try self.fields_to_zig(sinfo.getFieldsIterator());
                // methods
                try self.methods_to_zig("*@This()", sinfo.getMethodsIterator());
            }
            try self.println("}};", .{});
        }

        pub fn object_to_zig(self: *Self, oinfo: gintro.ObjectInfo) !void {
            if (oinfo.getTypeName()) |tname| {
                try self.println("// GObject name: {s}", .{tname});
            }
            try self.println("// Object", .{});
            const oname = oinfo.getName().?;

            // Object Struct
            try self.println("pub const {s} = struct {{", .{oname});
            self.indent();
            {
                defer self.unindent();

                // Attrs
                try self.attrs_to_zig(oinfo.getAttributeIterator());

                // fields
                try self.fields_to_zig(oinfo.getFieldsIterator());

                try self.println("}};", .{});
            }
            // Methods
            try self.println("pub fn Extend{s}(comptime Self: type, comptime Raw: type) type {{", .{oname});
            self.indent();
            {
                defer self.unindent();
                try self.println("return struct {{", .{});
                self.indent();
                {
                    defer self.unindent();

                    // Attrs
                    try self.attrs_to_zig(oinfo.getAttributeIterator());

                    // fields
                    try self.fields_to_zig(oinfo.getFieldsIterator());
                    // methods
                    try self.methods_to_zig("Self", oinfo.getMethodsIterator());
                }
                try self.println("}};", .{});
            }
            try self.println("}}", .{});
        }

        fn enum_to_zig(self: *Self, einfo: gintro.EnumInfo) !void {
            try self.println("// Enum", .{});
            try self.println("pub const {s} = enum({s}) {{", .{ einfo.getName().?, self.type_tag_to_zig(einfo.getStorageType()) });
            self.indent();
            {
                defer self.unindent();
                var iter = einfo.getValuesIterator();
                while (iter.next()) |value| {
                    defer value.unref();
                    try self.println("{s} = {d},", .{ self.get_name(value.getName().?), value.getValue() });
                }
            }
            try self.println("}};", .{});
        }

        pub fn baseinfo_to_zig(self: *Self, info: gintro.BaseInfo) !void {
            switch (info.getInfoType()) {
                .Struct => try self.struct_to_zig(info.uncheckedCast(gintro.StructInfo)),
                .Object => try self.object_to_zig(info.uncheckedCast(gintro.ObjectInfo)),
                .Constant => try self.constant_to_zig(info.uncheckedCast(gintro.ConstantInfo)),
                .Enum, .Flags => try self.enum_to_zig(info.uncheckedCast(gintro.EnumInfo)),
                .Function => {
                    var f = info.uncheckedCast(gintro.FunctionInfo);
                    if (f.isMethod()) {
                        try self.method_to_zig(null, f);
                    }
                },
                else => try self.println("// {?s}: {} not implemented", .{ info.getName(), info.getInfoType() }),
                // else => {}
            }
        }

        pub fn namespace_to_zig(self: *Self, namespace: gintro.Namespace, repo: ?gintro.Repository) !void {
            try self.namespace_to_zig_filtered(namespace, repo, null);
        }

        pub fn namespace_to_zig_filtered(self: *Self, namespace: gintro.Namespace, repo: ?gintro.Repository, only: ?ItemSet) !void {
            var repository = repo orelse gintro.Repository.default();
            self.current_module = try repository.require(namespace, .None);

            // Require dependencies
            const deps = repository.getDependencies(namespace).?;
            defer gintro.freeVString(deps);

            var typelibs = std.AutoArrayHashMap(gintro.TypeLib, gintro.Namespace).init(self.alloc);

            for (deps) |dep| {
                const dep2 = dep[0..std.mem.len(dep)];
                var sequences = std.mem.splitScalar(u8, dep2, '-');
                const name0 = sequences.next().?;
                const name = try self.alloc.dupeZ(u8, name0);
                const ver = try self.alloc.dupeZ(u8, sequences.next().?);
                const r = .{ .name = name, .version = ver };

                const deplib = try repository.require(r, .None);
                try typelibs.put(deplib, r);
            }

            var iterator = repository.getInfoIterator(namespace);
            while (iterator.next()) |info| {
                defer info.unref();
                if (only) |only2| {
                    if (!only2.contains(info.getName().?)) {
                        continue;
                    }
                }
                try self.baseinfo_to_zig(info);
            }

            // Add missing types
            var missed_iter = self.missing_types.iterator();
            while (missed_iter.next()) |item| {
                var missing_items_namespace = typelibs.get(item.key_ptr.*).?;
                const missing_items = item.value_ptr.*;
                try self.namespace_to_zig_filtered(missing_items_namespace, repository, missing_items);
            }
        }
    };
}

fn zig_emitter(writer: anytype, alloc: std.mem.Allocator) !ZigEmmiter(@TypeOf(writer)) {
    var a = std.heap.ArenaAllocator.init(alloc);
    var a2 = a.allocator();
    return .{ .writer = writer, .rename_table = try name_map(a2), .missing_types = MissingTypesMap.init(alloc), .allocator = a, .alloc = a2 };
}

pub fn name_map(allocator: std.mem.Allocator) !StringMap {
    var map = StringMap.init(allocator);
    try map.put("error", "error_");
    try map.put("type", "type_");
    try map.put("anytype", "anytype_");
    try map.put("continue", "continue_");
    try map.put("self", "self_");
    try map.put("enum", "enum_");
    try map.put("union", "union_");
    try map.put("struct", "struct_");
    try map.put("async", "async_");
    return map;
}

pub fn main() !void {
    var repo = gintro.Repository.default();
    var girepository = gintro.Namespace{ .name = "GIRepository", .version = "2.0" };
    var glib = gintro.Namespace{ .name = "GLib", .version = "2.0" };
    _ = glib;
    // var gi = gintro.Namespace{ .name = "Gtk", .version = "4.0" };
    var out = (try std.fs.cwd().createFile("/tmp/ex.zig", .{ .truncate = true }));
    defer out.close();
    var buf = std.io.bufferedWriter(out.writer());
    defer buf.flush() catch unreachable;
    var a = std.heap.GeneralPurposeAllocator(.{}){};
    var emitter = try zig_emitter(buf.writer(), a.allocator());
    try emitter.emit_prelude(&.{"girepository.h"});
    try emitter.namespace_to_zig(girepository, repo);
}
