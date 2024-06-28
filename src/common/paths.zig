const std = @import("std");
const Dir = std.fs.Dir;
const File = std.fs.File;
const Allocator = std.mem.Allocator;
const builtin = @import("builtin");
const OsTag = std.Target.Os.Tag;
const default_os = @import("root.zig").default_os;
const default_arch = @import("root.zig").default_arch;

pub const CommonPaths = struct {
    zigverm_root: Dir,
    install_dir: Dir,
    download_dir: Dir,
    overrides: File,

    const Self = @This();

    var zigverm_root_path: []const u8 = undefined;

    pub fn resolve(alloc: Allocator) !@This() {
        zigverm_root_path = try zigverm_dir(alloc);
        defer alloc.free(zigverm_root_path);
        const zigverm_root = try std.fs.openDirAbsolute(zigverm_root_path, .{});
        return CommonPaths{
            .zigverm_root = zigverm_root,
            .install_dir = try zigverm_root.openDir("installs/", .{ .iterate = true }),
            .download_dir = try zigverm_root.openDir("downloads/", .{ .iterate = true }),
            .overrides = try zigverm_root.createFile("overrides.json", .{ .truncate = false, .read = true }),
        };
    }

    fn zigverm_dir(alloc: Allocator) ![]const u8 {
        if (std.process.getEnvVarOwned(alloc, "ZIGVERM_ROOT_DIR")) |val| {
            return val;
        } else |_| {
            const home = try home_dir(alloc);
            defer alloc.free(home);
            return try std.fs.path.join(alloc, &.{ home, ".zigverm" });
        }
    }

    pub fn get_zigverm_root() []const u8 {
        return zigverm_root_path;
    }

    pub fn close(self: *Self) void {
        self.overrides.close();
        self.download_dir.close();
        self.install_dir.close();
        self.zigverm_root.close();
    }
};

pub extern "c" fn getuid() u32;

pub fn home_dir(alloc: Allocator) ![]const u8 {
    if (default_os == OsTag.windows) {
        if (std.process.getEnvVarOwned(alloc, "USERPROFILE")) |val| {
            return val;
        } else |_| {
            const homedrive = try std.process.getEnvVarOwned(alloc, "HOMEDRIVE");
            const homepath = try std.process.getEnvVarOwned(alloc, "HOMEPATH");
            defer alloc.free(homedrive);
            defer alloc.free(homepath);

            return try std.fs.path.join(alloc, &.{ homedrive, homepath });
        }
    }

    if (default_os.isBSD() or default_os.isDarwin() or default_os == OsTag.linux) {
        if (std.process.getEnvVarOwned(alloc, "HOME")) |val| {
            return val;
        } else |_| {
            switch (default_os) {
                OsTag.linux, OsTag.openbsd => {
                    return std.mem.span(std.c.getpwuid(getuid()).?.pw_dir.?);
                },
                else => {
                    @panic("Cannot determine home directory");
                },
            }
        }
    }
}
