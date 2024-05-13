const std = @import("std");
const Allocator = std.mem.Allocator;
const builtin = @import("builtin");
const OsTag = std.Target.Os.Tag;
const Rel = @import("main.zig").Rel;
const Sha256 = std.crypto.hash.sha2.Sha256;

const os = builtin.target.os.tag;
const arch = builtin.target.cpu.arch;

pub extern "c" fn getuid() u32;

pub const CommonDirs = struct {
    zigvm_root: std.fs.Dir,
    install_dir: std.fs.Dir,
    download_dir: std.fs.Dir,

    pub fn resolve_dirs(alloc: Allocator) !@This() {
        const zigvm_root = try std.fs.openDirAbsolute(try zigvm_dir(alloc), .{});
        return CommonDirs{
            .zigvm_root = zigvm_root,
            .install_dir = try zigvm_root.openDir("installs/", .{}),
            .download_dir = try zigvm_root.openDir("downloads/", .{}),
        };
    }

    fn zigvm_dir(alloc: Allocator) ![]const u8 {
        if (std.process.getEnvVarOwned(alloc, "ZIGVM_INSTALL_DIR")) |val| {
            return val;
        } else |_| {
            var buff = std.ArrayList(u8).init(alloc);
            try buff.appendSlice(try home_dir(alloc));
            try buff.appendSlice("/.zigvm");
            return buff.items;
        }
    }
};

pub fn streql(cmd: []const u8, key: []const u8) bool {
    return std.mem.eql(u8, cmd, key);
}

pub fn home_dir(alloc: Allocator) ![]const u8 {
    if (os == OsTag.windows) {
        if (std.process.getEnvVarOwned(alloc, "USERPROFILE")) |val| {
            return val;
        } else |_| {
            var buff = std.ArrayList(u8).init(alloc);
            try buff.appendSlice(try std.process.getEnvVarOwned(alloc, "HOMEDRIVE"));
            try buff.appendSlice(try std.process.getEnvVarOwned(alloc, "HOMEPATH"));
            return buff.items;
        }
    }

    if (os.isBSD() or os.isDarwin() or os == OsTag.linux) {
        if (std.process.getEnvVarOwned(alloc, "HOME")) |val| {
            return val;
        } else |_| {
            switch (os) {
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

pub fn target_name() []const u8 {
    return @tagName(arch) ++ "-" ++ @tagName(os);
}

pub fn dw_tarball_name(alloc: Allocator, rel: Rel) ![]const u8 {
    const release_string = rel.as_string();
    const dw_target = comptime target_name();
    return try std.mem.concat(alloc, u8, &[_][]const u8{ "zig-" ++ dw_target ++ "-", release_string, ".tar.xz.partial" });
}

pub fn release_name(alloc: Allocator, rel: Rel) ![]const u8 {
    const release_string = rel.as_string();
    const dw_target = comptime target_name();
    return try std.mem.concat(alloc, u8, &[_][]const u8{ "zig-" ++ dw_target ++ "-", release_string });
}

pub fn check_hash(hashstr: *const [64]u8, reader: anytype) !bool {
    var buff: [1024]u8 = undefined;

    var hasher = Sha256.init(.{});

    while (true) {
        const len = try reader.read(&buff);
        if (len == 0) {
            break;
        }
        hasher.update(buff[0..len]);
    }
    var hash: [32]u8 = undefined;
    _ = try std.fmt.hexToBytes(&hash, hashstr);
    return std.mem.eql(u8, &hasher.finalResult(), &hash);
}

pub fn extract_xz(alloc: Allocator, dirs: CommonDirs, rel: Rel, reader: anytype) !void {
    var xz = try std.compress.xz.decompress(alloc, reader);
    const release_dir = try dirs.install_dir.makeOpenPath(try release_name(alloc, rel), .{});
    try std.tar.pipeToFileSystem(release_dir, xz.reader(), .{ .strip_components = 1 });
}

pub fn check_not_installed(alloc: Allocator, rel: Rel, dirs: CommonDirs) !bool {
    return dirs.install_dir.access(try release_name(alloc, rel), .{}) == std.fs.Dir.AccessError.FileNotFound;
}
