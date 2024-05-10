const std = @import("std");
const Allocator = std.mem.Allocator;
const streql = @import("utils.zig").streql;

pub const Cli = union(enum) {
    Install: []const u8,
    Remove: []const u8,
};

pub fn read_args(alloc: Allocator) anyerror!Cli {
    var arg_iter = try std.process.argsWithAllocator(alloc);
    defer arg_iter.deinit();

    _ = arg_iter.next();

    var command: Cli = undefined;

    const cmd = arg_iter.next().?;

    if (streql(cmd, "install")) {
        const rel = arg_iter.next().?;
        command = Cli{ .Install = try alloc.dupe(u8, rel) };
    } else if (streql(cmd, "remove")) {
        const rel = arg_iter.next().?;
        command = Cli{ .Remove = try alloc.dupe(u8, rel) };
    }
    return command;
}
