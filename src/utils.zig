const std = @import("std");
const Allocator = std.mem.Allocator;
const builtin = @import("builtin");
const OsTag = std.Target.Os.Tag;

pub fn streql(cmd: []const u8, key: []const u8) bool {
    return std.mem.eql(u8, cmd, key);
}

pub fn home_dir(alloc: Allocator) ![]const u8 {
    const os = builtin.target.os.tag;

    if (os == OsTag.windows) {
        if (std.process.getEnvVarOwned(alloc, "USERPROFILE")) |val| {
            return val;
        } else {
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
            const getpwid = std.c.getpwuid;
            switch (os) {
                OsTag.linux => {
                    const getuid = std.os.linux.getuid;
                    return std.mem.span(getpwid(getuid()).?.pw_dir.?);
                },
                _ => {
                    @panic("Os not supported");
                },
            }
        }
    }
}
