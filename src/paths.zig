const std = @import("std");
const Dir = std.fs.Dir;
const File = std.fs.File;
const Allocator = std.mem.Allocator;
const utils = @import("utils.zig");

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
            try buff.appendSlice(try utils.home_dir(alloc));
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
