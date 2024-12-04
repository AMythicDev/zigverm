const std = @import("std");
const Allocator = std.mem.Allocator;
const streql = @import("common").streql;
const Version = @import("main.zig").Version;
const utils = @import("utils.zig");

const helptext =
    \\zigverm - A version manager for Zig
    \\
    \\zigverm [options] [command]
    \\
    \\Commands:
    \\      install <version>                   Install a specific version. Version can be any valid semantic version
    \\                                          or master or stable
    \\      override [DIRECTORY] <version>      Override the version of zig used under DIRECTORY. DIRECTORY can be
    \\                                              - Path to a directory, under which to override
    \\                                              - "default", to change the default version
    \\                                              - ommited to use the current directory
    \\      override-rm <DIRECTORY>             Override the version of zig used under DIRECTORY. DIRECTORY should
    \\                                          be path to a directory, for which to remove override
    \\      update [VERSION]                    Update version to its latest available point release, If [VERSION] is
    \\                                          not provided, it will update all installed versions
    \\      update-self                         Update zigverm itself
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

const cova = @import("cova");
pub const CommandT = cova.Command.Base();
pub const OptionT = CommandT.OptionT;
pub const ValueT = CommandT.ValueT;

pub const Install = struct {
    version: []const u8,
};

pub const Cli = CommandT{
    .name = "zigverm",
    .description = "A version manager for the Zig programming language",
    .sub_cmds = &.{
        .{
            .name = "install",
            .description = "Install a specific version",
            .vals = &.{
                ValueT.ofType([]const u8, .{ .name = "version", .description = "Version can be any valid semantic version or master or stable" }),
            },
        },
        .{
            .name = "remove",
            .description = "Remove a already installed specific version.",
            .vals = &.{
                ValueT.ofType([]const u8, .{ .name = "version", .description = "Version can be any valid semantic version or master or stable" }),
            },
        },
        .{
            .name = "override",
            .description = "Override the version of zig used",
            .vals = &.{
                ValueT.ofType([]const u8, .{ .name = "directory", .description = 
                \\DIRECTORY can be 
                \\                              - Path to a directory, under which to override
                \\                              - "default", to change the default version
                \\                              - ommited to use the current directory
                , .default_val = "" }),
                ValueT.ofType([]const u8, .{ .name = "version", .description = "Version can be any valid semantic version or master or stable" }),
            },
        },
        .{
            .name = "override-rm",
            .description = "Override the version of zig used",
            .vals = &.{
                ValueT.ofType([]const u8, .{ .name = "directory", .description = "DIRECTORY should be path to a directory, for which to remove override" }),
                ValueT.ofType([]const u8, .{ .name = "version", .description = "Version can be any valid semantic version or master or stable" }),
            },
        },
        .{
            .name = "std",
            .description = "Open the standard library documentation in the default web browser.",
            .vals = &.{
                ValueT.ofType([]const u8, .{ .name = "version", .description = "Opens for this VERSION. If not specified, opens for the active Zig version in the current directory.", .default_val = "" }),
            },
        },
        .{
            .name = "reference",
            .description = "Open the language reference in the default web browser.",
            .vals = &.{
                ValueT.ofType([]const u8, .{ .name = "version", .description = "Opens for this VERSION. If not specified, opens for the active version on the current directory.", .default_val = "" }),
            },
        },
        .{
            .name = "info",
            .description = "Show information about installations",
        },
        .{
            .name = "update-self",
            .description = "Update zigverm itself",
        },
    },
};

// ValueT.GenericT{
//     .string, .{
//         .name = "version",
//         .description = "install",
//     },
// },
