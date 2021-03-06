const std = @import("std");
const C = @cImport(
    @cInclude("girepository.h"),
);

pub const RepositoryLoadFlags = extern enum(c_int) {
    LoadLazy = C.G_IREPOSITORY_LOAD_FLAG_LAZY,
    _,
};

pub const String = struct {
    raw: [*:0]const C.gchar,
    should_free: bool = true,

    const Self = @This();

    pub fn deinit(self: Self) void {
        if (self.should_free) {
            C.g_free(self.raw);
        }
    }
    const cstr_align = @alignOf([*c]C.gchar);
    pub fn fromC(raw: [*c]const C.gchar) Self {
        return .{ .raw = raw };
    }
};

pub const VString = struct {
    raw: [*:0]const [*:0]const C.gchar,
    should_free: bool = true,

    const Self = @This();

    pub fn deinit(self: Self) void {
        if (self.should_free) {
            C.g_strfreev(vec);
        }
    }
    /// The returned string should not be `deinit`ed.
    pub fn get(self: *Self, id: usize) String {
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
/// # Context must have:
///  fn free(Get) void;
///  fn get(usize) ?Get;
///
///  As of now, I'm not sure what this type absolutely needs, to it may change.
///  Also, I'm not sure I like this paradigm I made, so if you have a better idea, DO make a pull request.
pub fn Iterator(comptime Get: type, Context: anytype) type {
    return struct {
        const Self = @This();

        i: usize,
        last: ?Get = null,
        context: Context,

        pub fn next(self: *Self) ?Get {
            if (self.last) |last| {
                self.context.free(last);
            }
            defer self.i += 1;
            return self.context.get(self.i);
        }
    };
}

// Auto Generated by `gen.py`
/// Enum that encodes all of Introspection's types.
const TypeInfo = enum(c_int) {
    Invalid = GI_INFO_TYPE_INVALID,
    Function = GI_INFO_TYPE_FUNCTION,
    Callback = GI_INFO_TYPE_CALLBACK,
    Struct = GI_INFO_TYPE_STRUCT,
    Boxed = GI_INFO_TYPE_BOXED,
    Enum = GI_INFO_TYPE_ENUM,
    Flags = GI_INFO_TYPE_FLAGS,
    Object = GI_INFO_TYPE_OBJECT,
    Interface = GI_INFO_TYPE_INTERFACE,
    Constant = GI_INFO_TYPE_CONSTANT,
    Union = GI_INFO_TYPE_UNION,
    Value = GI_INFO_TYPE_VALUE,
    Signal = GI_INFO_TYPE_SIGNAL,
    Vfunc = GI_INFO_TYPE_VFUNC,
    Property = GI_INFO_TYPE_PROPERTY,
    Field = GI_INFO_TYPE_FIELD,
    Arg = GI_INFO_TYPE_ARG,
    Type = GI_INFO_TYPE_TYPE,
    Unresolved = GI_INFO_TYPE_UNRESOLVED,

    pub fn fromC(en: C.GTypeInfo) @This() {
        return @intToEnum(TypeInfo, @enumToInt(en));
    }
};

pub const BaseInfo = struct {
    raw: *C.GIBaseInfo,

    const Self = @This();
    pub fn ref(self: *Self) Self {
        return .{ .raw = *C.g_base_info_ref(self.raw).? };
    }
    /// Call this when you're done with this `BaseInfo`.
    pub fn unref(self: Self) void {
        C.g_base_info_unref(self.raw);
    }
    /// Get the introspection type.
    pub fn getType(self: *const Self) TypeInfo {
        var value = C.g_base_info_get_type(self.raw);
        return TypeInfo.fromC(value);
    }
    pub fn getName(self: *const Self) ?String {
        const res = C.g_base_info_get_name(self.raw);
        if (res) |name| {
            return String.fromC(res);
        }
        return null;
    }
    const BaseInfoAttributesIterator = struct {
        raw: C.GIAttributeIter = .{
            0,
        },
        ref: *BaseInfo,

        fn next(self: *@This()) ?String[2] {
            var name: [*c]C.gchar = undefined;
            var val: [*c]C.gchar = undefined;
            if (C.g_base_info_iterate_attributes(self.ref.raw, &self.raw, &name, &val)) {
                const nstr = String.fromC(name);
                nstr.should_free = false;
                const vstr = String.fromC(val);
                vstr.should_free = false;
                return .{ String.fromC(name), String.fromC(val) };
            } else {
                return null;
            }
        }
    };
    pub fn getIterator(self: *Self) BaseInfoAttributesIterator {
        return .{ .ref = self.ref() };
    }
    pub fn fromC(raw: [*c]C.GIBaseInfo) Self {
        return .{ .raw = @alignCast(@alignOf(*BaseInfo), raw) };
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
        var raw = C.g_irepository_require(self.raw, namespace.name, namespace.version, @intToEnum(C.GIRepositoryLoadFlags, @enumToInt(flag)), &self.last_error);
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

    const InfoIteratorContext = struct {
        namespace: *Namespace,
        repo: *C.GIRepository,

        const Get = BaseInfo;

        pub fn get(self: *@This(), ii: usize) ?Get {
            var len = @intCast(usize, C.g_irepository_get_n_infos(self.repo, self.namespace.name));
            if (ii >= len) {
                return null;
            }
            return BaseInfo.fromC(C.g_irepository_get_info(self.repo, self.namespace.name, @intCast(i32, ii)));
        }
        pub fn free(self: *@This(), item: Get) void {
            item.unref();
        }
    };
    const InfoIterator = Iterator(BaseInfo, InfoIteratorContext);

    pub fn getInfoIterator(self: *Self, namespace: *Namespace) InfoIterator {
        return .{ .i = 0, .context = .{ .namespace = namespace, .repo = self.raw } };
    }
};

pub const Namespace = struct {
    name: [:0]const u8,
    version: [:0]const u8,
};
