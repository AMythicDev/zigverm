const std = @import("std");
const Allocator = std.mem.Allocator;
const builtin = @import("builtin");
const OsTag = std.Target.Os.Tag;

const os = builtin.target.os.tag;

pub extern "c" fn getuid() u32;

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
