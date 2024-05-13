const std = @import("std");
const Allocator = std.mem.Allocator;
const streql = @import("utils.zig").streql;

const helptext =
    \\zigvm - A version manager for Zig
    \\
    \\zigvm [options] [command]
    \\
    \\Commands:
    \\      install <version>    Install a specific version. Version can be any valid semantic version
    \\                           or master or stable
    \\      remove <version>     Remove a already installed specific version. Version can be any 
    \\                           valid semantic version or master or stable
    \\      info                 Show information about installations
    \\    
    \\Options:
    \\      -h  --help           Show this help message
    \\      -V  --version        Print version info
;

pub const Cli = union(enum) {
    install: []const u8,
    remove: []const u8,
    show,
};

pub fn read_args(alloc: Allocator) anyerror!Cli {
    var arg_iter = try std.process.argsWithAllocator(alloc);
    defer arg_iter.deinit();

    _ = arg_iter.next();

    var command: Cli = undefined;

    var cmd: []const u8 = undefined;

    {
        const trycmd = arg_iter.next();
        if (trycmd) |c| {
            cmd = c;
        } else {
            std.debug.print("Incorrect usage. Please see help by using --help\n", .{});
            std.process.exit(1);
        }
    }

    if (streql(cmd, "install")) {
        const rel = arg_iter.next().?;
        command = Cli{ .install = try alloc.dupe(u8, rel) };
    } else if (streql(cmd, "remove")) {
        const rel = arg_iter.next().?;
        command = Cli{ .remove = try alloc.dupe(u8, rel) };
    } else if (streql(cmd, "info")) {
        command = Cli.show;
    } else if (streql(cmd, "-h") or streql(cmd, "--help")) {
        std.debug.print("{s}\n", .{helptext});
        std.process.exit(0);
    } else {
        std.debug.print("Incorrect command {s}. Please see help by using --help\n", .{cmd});
        std.process.exit(1);
    }
    return command;
}
