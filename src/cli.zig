const std = @import("std");
const Allocator = std.mem.Allocator;
const streql = @import("common").streql;
const Version = @import("main.zig").Version;

const helptext =
    \\zigvm - A version manager for Zig
    \\
    \\zigvm [options] [command]
    \\
    \\Commands:
    \\      install <version>                   Install a specific version. Version can be any valid semantic version
    \\                                          or master or stable
    \\      override [DIRECTORY] <version>      Override the version of zig used under DIRECTORY. DIRECTORY can be
    \\                                              - Path to a directory, under which to override
    \\                                              - "default", to change the default version
    \\                                              - ommited to use the current directory
    \\      override-rm [DIRECTORY]             Override the version of zig used under DIRECTORY. DIRECTORY can be
    \\                                              - Path to a directory, under which to override
    \\                                              - "default", to change the default version
    \\                                              - An empty string to use the current directory
    \\      update [VERSION]                    Update version to its latest available point release, If [VERSION] is
    \\                                          not provided, it will update all installed versions
    \\      std [VERSION]                       Open the standard library documentation in the default web browser.
    \\                                          If [VERSION] is specified, it will open the documentation for that version
    \\                                          otherwise it will default to of the active version on the current directory.
    \\      reference [VERSION]                 Open the language reference in the default web browser.
    \\                                          If [VERSION] is specified, it will open the reference for that version
    \\                                          otherwise it will default to of the active version on the current directory.
    \\      remove <version>                    Remove a already installed specific version. Version can be any 
    \\                                          valid semantic version or master or stable
    \\      info                                Show information about installations
    \\    
    \\Options:
    \\      -h  --help           Show this help message
    \\      -V  --version        Print version info
;

pub const OverrideArrgs = struct {
    version: []const u8,
    directory: ?[]const u8,
};

pub const Cli = union(enum) {
    install: []const u8,
    remove: []const u8,
    show,
    override: OverrideArrgs,
    override_rm: ?[]const u8,
    update: ?[]const u8,
    std: ?[]const u8,
    reference: ?[]const u8,

    pub fn read_args(alloc: Allocator) anyerror!Cli {
        var arg_iter = try std.process.argsWithAllocator(alloc);
        defer arg_iter.deinit();

        _ = arg_iter.next();

        var command: Cli = undefined;

        var cmd: []const u8 = undefined;

        {
            const trycmd = arg_iter.next();
            if (trycmd) |c|
                cmd = c
            else
                incorrectUsage(null);
        }

        if (streql(cmd, "install")) {
            const rel = arg_iter.next().?;
            command = Cli{ .install = try alloc.dupe(u8, rel) };
        } else if (streql(cmd, "remove")) {
            const rel = arg_iter.next().?;
            command = Cli{ .remove = try alloc.dupe(u8, rel) };
        } else if (streql(cmd, "update")) {
            const rel = arg_iter.next();
            command = Cli{ .update = if (rel) |r| try alloc.dupe(u8, r) else null };
        } else if (streql(cmd, "std")) {
            const rel = arg_iter.next();
            command = Cli{ .std = if (rel) |r| try alloc.dupe(u8, r) else null };
        } else if (streql(cmd, "reference")) {
            const rel = arg_iter.next();
            command = Cli{ .reference = if (rel) |r| try alloc.dupe(u8, r) else null };
        } else if (streql(cmd, "info")) {
            command = Cli.show;
        } else if (streql(cmd, "-h") or streql(cmd, "--help")) {
            std.debug.print("{s}\n", .{helptext});
            std.process.exit(0);
        } else if (streql(cmd, "-V") or streql(cmd, "--version")) {
            std.debug.print("{s}\n", .{Version});
            std.process.exit(0);
        } else if (streql(cmd, "override")) {
            const rel_or_directory = arg_iter.next() orelse return incorrectUsage(null);
            const rel = arg_iter.next();

            var override_args = OverrideArrgs{ .version = undefined, .directory = null };

            if (rel != null) {
                override_args.version = try alloc.dupe(u8, rel.?);
                override_args.directory = try alloc.dupe(u8, rel_or_directory);
            } else {
                override_args.version = try alloc.dupe(u8, rel_or_directory);
            }

            command = Cli{ .override = override_args };
        } else if (streql(cmd, "override-rm")) {
            const directory = arg_iter.next();
            command = Cli{ .override_rm = directory };
        } else incorrectUsage(cmd);

        return command;
    }
};

fn incorrectUsage(cmd: ?[]const u8) noreturn {
    if (cmd != null) {
        std.debug.print("Incorrect usage for '{s}'. Please see help by using --help\n", .{cmd.?});
        std.process.exit(1);
    } else {
        std.debug.print("Incorrect usage. Please see help by using --help\n", .{});
        std.process.exit(1);
    }
}
