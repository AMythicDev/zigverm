const std = @import("std");
const builtin = @import("builtin");
const common = @import("common");
const CommonPaths = common.paths.CommonPaths;
const streql = common.streql;
const Rel = common.Rel;
const release_name = common.release_name;

const Allocator = std.mem.Allocator;
const OsTag = std.Target.Os.Tag;
const Sha256 = std.crypto.hash.sha2.Sha256;

const default_os = builtin.target.os.tag;
const default_arch = builtin.target.cpu.arch;

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
    const sv = if (common.Rel.completeSpec(version)) |_| true else |_| false;
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

pub fn check_not_installed(alloc: Allocator, rel: Rel, dirs: CommonPaths) !bool {
    return dirs.install_dir.access(try release_name(alloc, rel), .{}) == std.fs.Dir.AccessError.FileNotFound;
}

pub fn printStdOut(comptime fmt: []const u8, args: anytype) void {
    const stdout = std.io.getStdOut().writer();
    nosuspend stdout.print(fmt, args) catch return;
}
