const std = @import("std");
const Dir = std.Io.Dir;
const File = std.Io.File;
const Allocator = std.mem.Allocator;
const builtin = @import("builtin");
const OsTag = std.Target.Os.Tag;
const Environ = std.process.Environ;

const default_os = @import("root.zig").default_os;
const default_arch = @import("root.zig").default_arch;

pub const CommonPaths = struct {
    zigverm_root: Dir,
    install_dir: Dir,
    download_dir: Dir,
    overrides: File,

    const Self = @This();

    var allocator: Allocator = undefined;

    var zigverm_root_path: []const u8 = undefined;

    pub fn resolve(alloc: Allocator, io: std.Io, environ: *Environ.Map) !@This() {
        allocator = alloc;
        zigverm_root_path = try zigverm_dir(environ, alloc);
        const zigverm_root = try Dir.openDirAbsolute(io, zigverm_root_path, .{});
        return CommonPaths{
            .zigverm_root = zigverm_root,
            .install_dir = try zigverm_root.openDir(io, "installs/", .{ .iterate = true }),
            .download_dir = try zigverm_root.openDir(io, "downloads/", .{ .iterate = true }),
            .overrides = try zigverm_root.createFile(io, "overrides.json", .{ .truncate = false, .read = true }),
        };
    }

    fn zigverm_dir(environ: *Environ.Map, alloc: Allocator) ![]const u8 {
        return environ.get("ZIGVERM_ROOT_DIR") orelse {
            const home = try home_dir(alloc, environ);
            defer alloc.free(home);
            return try std.fs.path.join(alloc, &.{ home, ".zigverm" });
        };
    }

    pub fn get_zigverm_root() []const u8 {
        return zigverm_root_path;
    }

    pub fn close(self: *Self, io: std.Io) void {
        self.overrides.close(io);
        self.download_dir.close(io);
        self.install_dir.close(io);
        self.zigverm_root.close(io);
        allocator.free(zigverm_root_path);
    }
};

pub extern "c" fn getuid() u32;

pub fn home_dir(alloc: Allocator, environ_map: *Environ.Map) ![]const u8 {
    const env_var = if (default_os == .windows) "USERPROFILE" else "HOME";
    return environ_map.get(env_var) orelse {
        if (default_os == OsTag.windows) {
            const homedrive = environ_map.get("HOMEDRIVE") orelse {
                std.log.err("failed to determine home dir for current user", .{});
                return error.HomeDirectory;
            };
            const homepath = environ_map.get("HOMEPATH") orelse {
                std.log.err("failed to determine home dir for current user", .{});
                return error.HomeDirectory;
            };

            defer alloc.free(homedrive);
            defer alloc.free(homepath);

            return try std.fs.path.join(alloc, &.{ homedrive, homepath });
        } else {
            switch (default_os) {
                OsTag.linux, OsTag.openbsd => {
                    return std.mem.span(std.c.getpwuid(getuid()).?.dir.?);
                },
                else => {
                    std.log.err("failed to determine home dir for current user", .{});
                    return error.HomeDirectory;
                },
            }
        }
    };
}
