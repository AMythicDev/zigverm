const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Cli = union(enum) {
    Install: []const u8,
};

pub fn read_args(alloc: Allocator) anyerror!Cli {
    var arg_iter = try std.process.argsWithAllocator(alloc);
    defer arg_iter.deinit();

    _ = arg_iter.next();

    var command: Cli = undefined;

    if (std.mem.eql(u8, arg_iter.next().?, "install")) {
        const rel = arg_iter.next().?;
        command = Cli{ .Install = try alloc.dupe(u8, rel) };
    }

    return command;
}
