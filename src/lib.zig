const std = @import("std");
const C = @cImport(
    @cInclude("girepository.h"),
);

pub const RepositoryLoadFlags = extern enum(c_int) {
    LoadLazy = C.G_IREPOSITORY_LOAD_FLAG_LAZY,
    _,
};

pub const String = struct {
    raw: [*:0]C.gchar,
    pub fn deinit(self: @This()) void {
        C.g_free(self.raw);
    }
};
pub const VString = struct {
    raw: [*:0][*:0]C.gchar,
    pub fn deinit(self: @This()) void {
        C.g_strfreev(vec);
    }
    // The returned string should not be `deinit`ed.
    pub fn get(self: *@This(), id: usize) String {
        return .{ .raw = self.raw[id] };
    }
};

// Currently, acquiring a typelib from a repository is the only supported way.
pub const TypeLib = struct {
    raw: *C.GITypelib,
};

// This handles every error directly caused by the GObject Introspection library.
pub const RepositoryError = error{
    TypeLibNotFound,
    NamespaceMismatch,
    NamespaceVersionConflict,
    LibraryNotFound,
    UnknownError,
};

pub fn Iterator(comptime Get: type, Context: anytype) type {
    return struct {
        const Self = @This();

        i: usize,
        context: Context,

        pub fn next(self: *Self) ?Get {
            defer self.i += 1;
            return self.context.get(self.i);
        }
    };
}

pub const Repository = struct {
    raw: *C.GIRepository,
    last_error: ?*C.GError,

    const Self = @This();
    pub fn default() Self {
        return .{
            .last_error = null,
            .raw = C.g_irepository_get_default(),
        };
    }
    // Be aware the flag argument *will probably change* due to the API only specifying ONE flag.
    // If this returns an UnknownError, it happened in GLib. In that case, more information is avaliable at Repository.last_error.
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
    // You should free the resulting array with `VString.deinit`.
    pub fn getDependencies(self: *Self, namespace: *Namespace) ?VString {
        var raw = C.g_irepository_get_dependencies(self.raw, namespace.name) orelse return null;
        return .{ .raw = raw };
    }
    // See [getDependencies] for more info.
    pub fn getImmediateDependencies(self: *Self, namespace: *Namespace) ?VString {
        var raw = C.g_irepository_get_immediate_dependencies(self.raw, namespace.name) orelse return null;
        return .{ .raw = raw };
    }

    const InfoIteratorContext = struct {
        namespace: *Namespace,
        repo: *C.GIRepository,

        pub fn get(self: *@This(), ii: usize) ?*C.GIBaseInfo {
            var len = @intCast(usize, C.g_irepository_get_n_infos(self.repo, self.namespace.name));
            if (ii >= len) {
                return null;
            }
            return C.g_irepository_get_info(self.repo, self.namespace.name, @intCast(i32, ii));
        }
    };
    const InfoIterator = Iterator(*C.GIBaseInfo, InfoIteratorContext);

    pub fn getInfoIterator(self: *Self, namespace: *Namespace) InfoIterator {
        return .{ .i = 0, .context = .{ .namespace = namespace, .repo = self.raw } };
    }
};

pub const Namespace = struct {
    name: [:0]const u8,
    version: [:0]const u8,
};
