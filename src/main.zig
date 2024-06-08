const std = @import("std");
const utils = @import("utils.zig");
const builtin = @import("builtin");
const Cli = @import("cli.zig").Cli;
const common = @import("common");
const Client = std.http.Client;

const paths = common.paths;
const json = std.json;
const File = std.fs.File;
const Allocator = std.mem.Allocator;
const streql = common.streql;
const CommonPaths = paths.CommonPaths;
const Rel = common.Rel;
const install = @import("install.zig");

pub const Version = "0.1.0";

pub fn main() !void {
    var aa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = aa.allocator();

    const command = try Cli.read_args(alloc);

    var cp = try CommonPaths.resolve(alloc);
    defer cp.clone();

    switch (command) {
        Cli.install => |version| {
            var rel = try Rel.releasefromVersion(version);
            if (!(try utils.check_not_installed(alloc, rel, cp))) {
                std.log.err("Version already installled. Quitting", .{});
                std.process.exit(0);
            }

            var client = Client{ .allocator = alloc };
            defer client.deinit();

            const resp = try install.get_json_dslist(&client);
            const releases = try json.parseFromSliceLeaky(json.Value, alloc, resp.body[0..resp.length], .{});

            try install.install_release(alloc, &client, releases, &rel, cp);
        },
        Cli.remove => |version| {
            const rel = try Rel.releasefromVersion(version);
            try remove_release(alloc, rel, cp);
        },
        Cli.show => {
            try show_info(alloc, cp);
        },
        Cli.override => |oa| {
            var override_args = oa;
            const rel = try Rel.releasefromVersion(override_args.version);
            if (override_args.directory != null and !streql(override_args.directory.?, "default")) {
                override_args.directory = try std.fs.realpathAlloc(alloc, override_args.directory.?);
            }
            const directory = override_args.directory orelse try std.process.getCwdAlloc(alloc);
            try override(alloc, cp, rel, directory);
        },
        Cli.override_rm => |dir| {
            const directory = dir orelse try std.process.getCwdAlloc(alloc);
            try override_rm(alloc, cp, directory);
        },
        Cli.update => |version| {
            if (version == null) @panic("Updating all versions is not supported yet");
            try update_version(alloc, version.?, cp);
        },
    }
}

fn remove_release(alloc: Allocator, rel: Rel, cp: CommonPaths) !void {
    if ((try utils.check_not_installed(alloc, rel, cp))) {
        std.log.err("Version not installled. Quitting", .{});
        std.process.exit(0);
    }
    const release_dir = try common.release_name(alloc, rel);
    try cp.install_dir.deleteTree(release_dir);
    std.log.info("Removed {s}", .{release_dir});
}

fn show_info(alloc: Allocator, cp: CommonPaths) !void {
    std.debug.print("zigvm root:\t{s}\n\n", .{CommonPaths.get_zigvm_root()});
    var iter = cp.install_dir.iterate();

    const dir_to_check = try std.process.getCwdAlloc(alloc);
    const active_version = try common.overrides.active_version(alloc, cp, dir_to_check);

    std.debug.print("Active version: {s} (from '{s}')\n\n", .{ active_version.ver, active_version.from });
    std.debug.print("Installed releases:\n\n", .{});

    var n: u8 = 1;
    while (try iter.next()) |i| {
        if (!utils.check_install_name(i.name)) {
            continue;
        }
        std.debug.print("{d}.  {s}\n", .{ n, i.name });
        n += 1;
    }
}

fn override(alloc: Allocator, cp: CommonPaths, rel: Rel, directory: []const u8) !void {
    var overrides = try common.overrides.read_overrides(alloc, cp);
    try overrides.put(directory, json.Value{ .string = rel.releaseName() });
    try common.overrides.write_overrides(overrides, cp);
}

fn override_rm(alloc: Allocator, cp: CommonPaths, directory: []const u8) !void {
    var overrides = try common.overrides.read_overrides(alloc, cp);
    _ = overrides.orderedRemove(directory);
    try common.overrides.write_overrides(overrides, cp);
}

fn update_version(alloc: Allocator, version: []const u8, cp: CommonPaths) !void {
    var rel = try Rel.releasefromVersion(version);

    // Find updated patch release by resolving
    var client = Client{ .allocator = alloc };
    defer client.deinit();
    const resp = try install.get_json_dslist(&client);
    const releases = try json.parseFromSliceLeaky(json.Value, alloc, resp.body[0..resp.length], .{});

    if (try utils.check_not_installed(alloc, rel, cp)) {
        try install.install_release(alloc, &client, releases, &rel, cp);
        return;
    }

    if (rel.release == common.ReleaseSpec.FullVersionSpec)
        std.debug.print("\t{s}    :    Up to date\n", .{version});

    try install.install_release(alloc, &client, releases, &rel, cp);
}
