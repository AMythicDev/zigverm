const std = @import("std");
const Dir = std.fs.Dir;
const File = std.fs.File;
const Allocator = std.mem.Allocator;
const builtin = @import("builtin");
const OsTag = std.Target.Os.Tag;

const default_os = builtin.target.os.tag;
const default_arch = builtin.target.cpu.arch;

pub const CommonPaths = struct {
    zigvm_root: Dir,
    install_dir: Dir,
    download_dir: Dir,
    overrides: File,

    const Self = @This();

    var zigvm_root_path: []const u8 = undefined;

    pub fn resolve(alloc: Allocator) !@This() {
        zigvm_root_path = try zigvm_dir(alloc);
        const zigvm_root = try std.fs.openDirAbsolute(zigvm_root_path, .{});
        return CommonPaths{
            .zigvm_root = zigvm_root,
            .install_dir = try zigvm_root.openDir("installs/", .{ .iterate = true }),
            .download_dir = try zigvm_root.openDir("downloads/", .{ .iterate = true }),
            .overrides = try zigvm_root.createFile("overrides.json", .{ .truncate = false, .read = true }),
        };
    }

    fn zigvm_dir(alloc: Allocator) ![]const u8 {
        if (std.process.getEnvVarOwned(alloc, "ZIGVM_ROOT_DIR")) |val| {
            return val;
        } else |_| {
            var buff = std.ArrayList(u8).init(alloc);
            try buff.appendSlice(try home_dir(alloc));
            try buff.appendSlice("/.zigvm");
            return buff.items;
        }
    }

    pub fn get_zigvm_root() []const u8 {
        return zigvm_root_path;
    }

    pub fn clone(self: *Self) void {
        self.overrides.close();
        self.download_dir.close();
        self.install_dir.close();
        self.zigvm_root.close();
    }
};

pub extern "c" fn getuid() u32;

pub fn home_dir(alloc: Allocator) ![]const u8 {
    if (default_os == OsTag.windows) {
        if (std.process.getEnvVarOwned(alloc, "USERPROFILE")) |val| {
            return val;
        } else |_| {
            var buff = std.ArrayList(u8).init(alloc);
            try buff.appendSlice(try std.process.getEnvVarOwned(alloc, "HOMEDRIVE"));
            try buff.appendSlice(try std.process.getEnvVarOwned(alloc, "HOMEPATH"));
            return buff.items;
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
