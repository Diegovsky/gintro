const std = @import("std");
const C = @cImport(@cInclude("girepository.h"));

pub const RepositoryLoadFlags = enum(c_int) {
    LoadLazy = C.G_IREPOSITORY_LOAD_FLAG_LAZY,
    _,
};

pub const Namespace = struct {
    name: [*c]const u8,
    version: [*c]const u8,
};

pub fn gbool(value: C.gboolean) bool {
    return value == C.TRUE;
}

pub const String = struct {
    raw: [*c]const C.gchar,
    should_free: bool = true,

    const Self = @This();

    pub fn format(value: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        try std.fmt.formatText(value.slice(), fmt, options, writer);
    }

    pub fn new_borrowed(str: [*:0]const u8) Self {
        return .{
            .raw = str,
            .should_free = false,
        };
    }

    pub fn new_copied(str: [*:0]const u8) Self {
        return .{
            .raw = C.g_strdup(str),
        };
    }

    pub fn copy(self: Self) Self {
        return Self.new_copied(self.raw);
    }

    pub fn slice(self: Self) []const u8 {
        const strlen = std.mem.len(self.raw);
        std.debug.print("\nStrlen: {d}\n", .{strlen});
        return self.raw[0..strlen];
    }

    pub fn deinit(self: Self) void {
        if (self.should_free) {
            C.g_free(self.raw);
        }
    }

    pub fn fromC(raw: [*c]const C.gchar, should_free: bool) Self {
        if (raw == null) {
            return .{ .raw = "", .should_free = should_free };
        }
        return .{ .raw = raw, .should_free = should_free };
    }
};

pub const VString = struct {
    raw: [*:0]const [*:0]const C.gchar,
    should_free: bool = true,

    const Self = @This();

    pub fn deinit(self: Self) void {
        if (self.should_free) {
            C.g_strfreev(self.raw);
        }
    }
    /// The returned string should not be `deinit`ed.
    pub fn get(self: Self, id: usize) String {
        return .{ .raw = self.raw[id] };
    }

    pub fn fromC(raw: [*c]const [*c]const C.gchar) Self {
        return .{ .raw = @alignCast(@alignOf([*:0][*:0]C.gchar), raw) };
    }
};

/// Currently, acquiring a typelib from a repository is the only supported way.
pub const TypeLib = struct {
    raw: *C.GITypelib,
};

/// This handles every error directly caused by the GObject Introspection library.
pub const RepositoryError = error{
    TypeLibNotFound,
    NamespaceMismatch,
    NamespaceVersionConflict,
    LibraryNotFound,
    UnknownError,
};

/// A generic iterator type used to iterate over Introspection's types that follow this pattern:
///  int <Type>_get_n_<properties>s()
///  int <Type>_get_<property>()
///
///  As of now, I'm not sure what this type absolutely needs, to it may change.
///  Also, I'm not sure I like this paradigm I made, so if you have a better idea, DO make a pull request.
fn Iterator(comptime Iterable: type, comptime Get: type) type {
    return struct {
        iterable: Iterable,
        len: c_int,
        i: c_int,

        pub fn new(iterable: Iterable) @This() {
            const len = iterable.len();
            return .{ .iterable = iterable, .len = len, .i = 0 };
        }

        pub fn next(self: *@This()) ?Get {
            // std.debug.print("Len {s}: {d}\n", .{ @typeName(@This()), self.len });
            if (self.i >= self.len) {
                return null;
            }
            defer self.i += 1;
            return Get.fromC(self.iterable.index(self.i));
        }
    };
}

// Auto Generated by `gen.py`
/// Enum that encodes all of Introspection's types.
pub const InfoType = enum(c_int) {
    Invalid = C.GI_INFO_TYPE_INVALID,
    Function = C.GI_INFO_TYPE_FUNCTION,
    Callback = C.GI_INFO_TYPE_CALLBACK,
    Struct = C.GI_INFO_TYPE_STRUCT,
    Boxed = C.GI_INFO_TYPE_BOXED,
    Enum = C.GI_INFO_TYPE_ENUM,
    Flags = C.GI_INFO_TYPE_FLAGS,
    Object = C.GI_INFO_TYPE_OBJECT,
    Interface = C.GI_INFO_TYPE_INTERFACE,
    Constant = C.GI_INFO_TYPE_CONSTANT,
    Union = C.GI_INFO_TYPE_UNION,
    Value = C.GI_INFO_TYPE_VALUE,
    Signal = C.GI_INFO_TYPE_SIGNAL,
    Vfunc = C.GI_INFO_TYPE_VFUNC,
    Property = C.GI_INFO_TYPE_PROPERTY,
    Field = C.GI_INFO_TYPE_FIELD,
    Arg = C.GI_INFO_TYPE_ARG,
    Type = C.GI_INFO_TYPE_TYPE,
    Unresolved = C.GI_INFO_TYPE_UNRESOLVED,

    pub fn fromC(en: c_uint) @This() {
        return @intToEnum(InfoType, en);
    }
};

/// Gnome docs says different repos might never be supported, but we make the assumption that it's a possibility.
pub const Repository = struct {
    raw: *C.GIRepository,
    last_error: ?*C.GError,

    const Self = @This();

    /// Returns the default Repository of this process.
    pub fn default() Self {
        return .{
            .last_error = null,
            .raw = C.g_irepository_get_default(),
        };
    }
    /// Be aware the flag argument *will probably change* due to the API only specifying ONE flag.
    /// If this returns an UnknownError, it happened in GLib. In that case, more information is avaliable at Repository.last_error.
    pub fn require(self: *Self, namespace: *Namespace, flag: RepositoryLoadFlags) RepositoryError!TypeLib {
        var raw = C.g_irepository_require(self.raw, namespace.name, namespace.version, @intCast(c_uint, @enumToInt(flag)), &self.last_error);
        if (raw) |ptr| {
            return TypeLib{ .raw = ptr };
        } else if (self.last_error) |err| {
            return switch (err.code) {
                C.G_IREPOSITORY_ERROR_TYPELIB_NOT_FOUND => error.TypeLibNotFound,
                C.G_IREPOSITORY_ERROR_NAMESPACE_MISMATCH => error.NamespaceMismatch,
                C.G_IREPOSITORY_ERROR_NAMESPACE_VERSION_CONFLICT => error.NamespaceVersionConflict,
                C.G_IREPOSITORY_ERROR_LIBRARY_NOT_FOUND => error.LibraryNotFound,
                else => error.UnknownError,
            };
        } else {
            unreachable;
        }
    }
    /// You should free the resulting array with `VString.deinit`.
    pub fn getDependencies(self: *Self, namespace: *Namespace) ?VString {
        var raw = C.g_irepository_get_dependencies(self.raw, namespace.name) orelse return null;
        return .{ .raw = raw };
    }
    /// See [getDependencies] for more info.
    pub fn getImmediateDependencies(self: *Self, namespace: *Namespace) ?VString {
        var raw = C.g_irepository_get_immediate_dependencies(self.raw, namespace.name) orelse return null;
        return .{ .raw = raw };
    }

    const InfoIterator = Iterator(struct {
        namespace: *Namespace,
        repo: *C.GIRepository,

        const Raw = C.GIBaseInfo;

        pub fn len(self: @This()) i32 {
            return C.g_irepository_get_n_infos(self.repo, self.namespace.name);
        }

        pub fn index(self: @This(), i: i32) *Raw {
            return C.g_irepository_get_info(self.repo, self.namespace.name, i);
        }
    }, BaseInfo);

    pub fn getInfoIterator(self: *Self, namespace: *Namespace) InfoIterator {
        return InfoIterator.new(.{ .namespace = namespace, .repo = self.raw });
    }
};

pub const BaseInfo = struct {
    raw: *Raw,

    const Self = @This();
    const Raw = C.GIBaseInfo;

    pub fn ref(self: *Self) Self {
        return .{ .raw = C.g_base_info_ref(self.raw).? };
    }
    /// Call this when you're done with this `BaseInfo`.
    pub fn unref(self: Self) void {
        C.g_base_info_unref(self.raw);
    }
    /// Get the introspection type.
    pub fn getType(self: *const Self) InfoType {
        var value = C.g_base_info_get_type(self.raw);
        return InfoType.fromC(value);
    }
    pub fn getName(self: *const Self) ?String {
        const res = C.g_base_info_get_name(self.raw);
        if (res) |name| {
            return String.fromC(name, false);
        }
        return null;
    }

    pub fn is(value: anytype) bool {
        return C.GI_IS_BASE_INFO(value.raw);
    }

    pub fn tryCast(self: *const Self, comptime T: type) ?T {
        if (T.is(self)) {
            return T.fromC(@ptrCast(*T.Raw, self.raw));
        }
        return null;
    }

    const BaseInfoAttributesIterator = struct {
        raw: C.GIAttributeIter,
        ref: BaseInfo,

        pub fn new(ref_: BaseInfo) @This() {
            return .{
                .raw = std.mem.zeroes(C.GIAttributeIter),
                .ref = ref_,
            };
        }

        pub fn next(self: *@This()) ?[2]String {
            var name: [*c]C.gchar = undefined;
            var val: [*c]C.gchar = undefined;
            if (C.g_base_info_iterate_attributes(self.ref.raw, &self.raw, &name, &val) == 1) {
                const nstr = String.fromC(name);
                const vstr = String.fromC(val);
                return .{ nstr, vstr };
            } else {
                return null;
            }
        }
    };

    pub fn getAttributeIterator(self: Self) BaseInfoAttributesIterator {
        return BaseInfoAttributesIterator.new(self);
    }

    pub fn fromC(raw: [*c]Raw) Self {
        return .{ .raw = @alignCast(@alignOf(*Raw), raw) };
    }
};

pub const StructInfo = struct {
    raw: *Raw,

    pub const Raw = C.GIStructInfo;
    pub const Super = BaseInfo;
    const Self = @This();

    // Boilerplate
    pub fn fromC(raw: [*c]Raw) Self {
        return Self{ .raw = raw };
    }

    pub fn ref(self: Self) Self {
        const ptr = Self.fromC(self.super().ref().raw);
        if (@ptrToInt(ptr) != @ptrToInt(self.raw)) {
            unreachable;
        }
        return ptr;
    }

    pub fn super(self: Self) Super {
        return Super.fromC(@ptrCast(*Super.Raw, self.raw));
    }

    pub fn unref(self: Self) void {
        self.super().unref();
    }

    pub fn is(value: anytype) bool {
        return C.GI_IS_STRUCT_INFO(value.raw);
    }

    // Subclass code
    const FieldsIterator = Iterator(struct {
        raw: *FieldInfo.Raw,

        pub fn index(self: @This(), i: c_int) *FieldInfo.Raw {
            return C.g_struct_info_get_field(self.raw, i);
        }
        pub fn len(self: @This()) c_int {
            return C.g_struct_info_get_n_fields(self.raw);
        }
    }, FieldInfo);

    pub fn getFieldsIterator(self: Self) FieldsIterator {
        return FieldsIterator.new(.{ .raw = self.raw });
    }
};

pub const TypeInfoFlags = struct {
    raw: C.GIFieldInfo,

    pub fn isReadable(self: @This()) bool {
        return (self.raw & C.GI_FIELD_IS_READABLE) != 0;
    }

    pub fn isWritable(self: @This()) bool {
        return (self.raw & C.GI_FIELD_IS_WRITABLE) != 0;
    }
};

pub const FieldInfo = struct {
    raw: *Raw,

    pub const Raw = C.GIFieldInfo;
    pub const Super = BaseInfo;
    const Self = @This();

    // Boilerplate
    pub fn fromC(raw: [*c]Raw) Self {
        return Self{ .raw = raw };
    }

    pub fn ref(self: Self) Self {
        return Self.fromC(self.super().ref().raw);
    }

    pub fn super(self: Self) Super {
        return Super.fromC(@ptrCast(*Super.Raw, self.raw));
    }

    pub fn tryCast(self: Self, comptime T: type) ?T {
        return self.super().tryCast(T);
    }

    pub fn unref(self: Self) void {
        self.super().unref();
    }

    // Subclass code
    pub fn getType(self: Self) TypeInfo {
        return TypeInfo.fromC(C.g_field_info_get_type(self.raw));
    }
    pub fn getFlags(self: Self) TypeInfoFlags {
        return TypeInfoFlags{ .raw = C.g_field_info_get_flags(self.raw) };
    }

    pub fn getSize(self: Self) usize {
        return @intCast(usize, C.g_field_info_get_size(self.raw));
    }

    pub fn getOffset(self: Self) usize {
        return @intCast(usize, C.g_field_info_get_offset(self.raw));
    }
};

const TypeTag = enum(c_int) {
    Void = C.GI_TYPE_TAG_VOID,
    Boolean = C.GI_TYPE_TAG_BOOLEAN,
    Int8 = C.GI_TYPE_TAG_INT8,
    Uint8 = C.GI_TYPE_TAG_UINT8,
    Int16 = C.GI_TYPE_TAG_INT16,
    Uint16 = C.GI_TYPE_TAG_UINT16,
    Int32 = C.GI_TYPE_TAG_INT32,
    Uint32 = C.GI_TYPE_TAG_UINT32,
    Int64 = C.GI_TYPE_TAG_INT64,
    Uint64 = C.GI_TYPE_TAG_UINT64,
    Float = C.GI_TYPE_TAG_FLOAT,
    Double = C.GI_TYPE_TAG_DOUBLE,
    Gtype = C.GI_TYPE_TAG_GTYPE,
    Utf8 = C.GI_TYPE_TAG_UTF8,
    Filename = C.GI_TYPE_TAG_FILENAME,
    Array = C.GI_TYPE_TAG_ARRAY,
    Interface = C.GI_TYPE_TAG_INTERFACE,
    Glist = C.GI_TYPE_TAG_GLIST,
    Gslist = C.GI_TYPE_TAG_GSLIST,
    Ghash = C.GI_TYPE_TAG_GHASH,
    Error = C.GI_TYPE_TAG_ERROR,
    Unichar = C.GI_TYPE_TAG_UNICHAR,

    fn fromC(raw: c_int) @This() {
        return @intToEnum(@This(), raw);
    }
};

pub const TypeInfo = struct {
    raw: *Raw,

    pub const Raw = C.GITypeInfo;
    pub const Super = BaseInfo;
    const Self = @This();

    // Boilerplate
    pub fn fromC(raw: [*c]Raw) Self {
        return Self{ .raw = raw };
    }

    pub fn ref(self: Self) Self {
        return Self.fromC(self.super().ref().raw);
    }

    pub fn super(self: Self) Super {
        return Super.fromC(@ptrCast(*Super.Raw, self.raw));
    }

    pub fn tryCast(self: Self, comptime T: type) ?T {
        return self.super().tryCast(T);
    }

    pub fn unref(self: Self) void {
        self.super().unref();
    }

    // Subclass code
    pub fn getTypeName(self: Self) String {
        var str = C.g_registered_type_info_get_type_name(self.raw);
        return String.fromC(str, false);
    }

    pub fn getGType(self: Self) C.GType {
        return C.g_registered_type_info_get_type_name(self.raw);
    }

    pub fn getTag(self: Self) TypeTag {
        return TypeTag.fromC(C.g_registered_type_info_get_tag(self.raw));
    }
};

fn wrap(comptime T: type) type {
    const Raw = T.Raw;
    const Super = T.Super;
    const Self = T;
    return struct {
        pub usingnamespace T;
        pub fn fromC(raw: [*c]Raw) Self {
            return Self{ .raw = raw };
        }

        pub fn ref(self: Self) Self {
            return Self.fromC(self.super().ref().raw);
        }

        pub fn super(self: Self) Super {
            return Super.fromC(@ptrCast(*Super.Raw, self.raw));
        }

        pub fn tryCast(self: Self, comptime R: type) ?R {
            return self.super().tryCast(R);
        }

        pub fn unref(self: Self) void {
            self.super().unref();
        }
    };
}

pub const RegisteredTypeInfo = struct {
    raw: *Raw,

    pub const Raw = C.GIRegisteredTypeInfo;
    pub const Super = BaseInfo;
    const Self = @This();

    // Boilerplate
    pub fn fromC(raw: [*c]Raw) Self {
        return Self{ .raw = raw };
    }

    pub fn ref(self: Self) Self {
        return Self.fromC(self.super().ref().raw);
    }

    pub fn super(self: Self) Super {
        return Super.fromC(@ptrCast(*Super.Raw, self.raw));
    }

    pub fn tryCast(self: Self, comptime T: type) ?T {
        return self.super().tryCast(T);
    }

    pub fn unref(self: Self) void {
        self.super().unref();
    }

    // Subclass code
    fn getTypeName(self: Self) String {
        var str = C.g_registered_type_info_get_type_name(self.raw);
        return String.fromC(str, false);
    }

    fn getGType(self: Self) C.GType {
        return C.g_registered_type_info_get_type_name(self.raw);
    }
};
