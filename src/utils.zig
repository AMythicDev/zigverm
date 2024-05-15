const std = @import("std");
const Allocator = std.mem.Allocator;
const builtin = @import("builtin");
const OsTag = std.Target.Os.Tag;
const Rel = @import("main.zig").Rel;
const Sha256 = std.crypto.hash.sha2.Sha256;

const default_os = builtin.target.os.tag;
const default_arch = builtin.target.cpu.arch;

pub extern "c" fn getuid() u32;

pub const CommonDirs = struct {
    zigvm_root: std.fs.Dir,
    install_dir: std.fs.Dir,
    download_dir: std.fs.Dir,

    var zigvm_root_path: []const u8 = undefined;

    pub fn resolve_dirs(alloc: Allocator) !@This() {
        zigvm_root_path = try zigvm_dir(alloc);
        const zigvm_root = try std.fs.openDirAbsolute(zigvm_root_path, .{});
        return CommonDirs{
            .zigvm_root = zigvm_root,
            .install_dir = try zigvm_root.openDir("installs/", .{ .iterate = true }),
            .download_dir = try zigvm_root.openDir("downloads/", .{ .iterate = true }),
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
};

pub fn streql(cmd: []const u8, key: []const u8) bool {
    return std.mem.eql(u8, cmd, key);
}

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

pub fn target_name() []const u8 {
    return @tagName(default_arch) ++ "-" ++ @tagName(default_os);
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

pub fn check_install_name(name: []const u8) bool {
    if (!std.mem.startsWith(u8, name, "zig-")) {
        return false;
    }
    var components = std.mem.split(u8, name[4..], "-");

    const arch = components.next();
    const os = components.next();
    if (!is_valid_arch_os(arch, os)) {
        return false;
    }
    const version = components.next() orelse return false;
    const sv = if (std.SemanticVersion.parse(version)) |_| true else |_| false;
    if (!streql(version, "stable") and !streql(version, "master") and !sv) {
        return false;
    }

    return true;
}

pub fn is_valid_arch_os(arch: ?[]const u8, os: ?[]const u8) bool {
    const arch_fields = @typeInfo(std.Target.Cpu.Arch).Enum.fields;
    comptime var archs: [arch_fields.len][]const u8 = undefined;
    comptime {
        for (arch_fields, 0..) |a, i| {
            archs[i] = a.name;
        }
    }
    const osfields = @typeInfo(std.Target.Os.Tag).Enum.fields;
    comptime var oses: [osfields.len][]const u8 = undefined;
    comptime {
        for (osfields, 0..) |o, i| {
            oses[i] = o.name;
        }
    }

    var result = false;
    if (arch) |a| {
        for (archs) |as| {
            if (streql(as, a)) {
                result = true;
                break;
            }
        }
    }
    if (os) |o| {
        for (oses) |t| {
            if (streql(o, t)) {
                result = true;
                break;
            }
        }
    }

    return result;
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
