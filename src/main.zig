const std = @import("std");
const utils = @import("utils.zig");
const builtin = @import("builtin");
const Cli = @import("cli.zig").Cli;
const common = @import("common");
const update_self = @import("update-self.zig");

const Client = std.http.Client;
const http = std.http;
const paths = common.paths;
const json = std.json;
const File = std.fs.File;
const Allocator = std.mem.Allocator;
const streql = common.streql;
const CommonPaths = paths.CommonPaths;
const Release = common.Release;
const install = @import("install.zig");

pub const Version = "0.4.0";

pub fn main() !void {
    var aa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = aa.allocator();

    const command = try Cli.read_args(alloc);

    var cp = try CommonPaths.resolve(alloc);
    defer cp.close();

    switch (command) {
        Cli.install => |version| {
            var rel = try Release.releasefromVersion(version);
            if (cp.install_dir.openDir(try common.release_name(alloc, rel), .{})) |_| {
                std.log.err("Version already installled. Quitting", .{});
                std.process.exit(0);
            } else |_| {}

            var client = Client{ .allocator = alloc };
            defer client.deinit();

            const resp = try install.get_json_dslist(&client);
            const releases = try json.parseFromSliceLeaky(json.Value, alloc, resp.body[0..resp.length], .{});

            try install.install_release(alloc, &client, releases, &rel, cp);
        },
        Cli.remove => |version| {
            const rel = try Release.releasefromVersion(version);
            try remove_release(alloc, rel, cp);
        },
        Cli.show => try show_info(alloc, cp),
        Cli.std => |ver| open_std(ver),
        Cli.reference => |ver| open_reference(alloc, ver),
        Cli.override => |oa| {
            var override_args = oa;
            const rel = try Release.releasefromVersion(override_args.version);
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
        Cli.update_self => try update_self.update_self(alloc, cp),
        Cli.update => |version_possible| update_zig_installation(alloc, cp, version_possible),
    }
}

fn remove_release(alloc: Allocator, rel: Release, cp: CommonPaths) !void {
    if (cp.install_dir.openDir(try common.release_name(alloc, rel), .{})) |_| {
        std.log.err("Version not installled. Quitting", .{});
        std.process.exit(0);
    } else |_| {}
    const release_dir = try common.release_name(alloc, rel);
    try cp.install_dir.deleteTree(release_dir);
    std.log.info("Removed {s}", .{release_dir});
}

fn open_std(alloc: Allocator, ver: []const u8) void {
    var best_match: []const u8 = undefined;
    if (ver) |v| {
        best_match = v;
    } else {
        const dir_to_check = try std.process.getCwdAlloc(alloc);
        var overrides = try common.overrides.read_overrides(alloc, cp);
        defer overrides.deinit();

        best_match = try alloc.dupe(u8, (try overrides.active_version(dir_to_check)).ver);
    }

    const zig_path = try std.fs.path.join(alloc, &.{
        common.paths.CommonPaths.get_zigverm_root(),
        "installs/",
        try common.release_name(alloc, try common.Release.releasefromVersion(best_match)),
        "zig",
    });

    var executable = std.ArrayList([]const u8).init(alloc);
    try executable.append(zig_path);
    try executable.append("std");
    var child = std.process.Child.init(executable.items, alloc);
    const term = try child.spawnAndWait();
    std.process.exit(term.Exited);
}

fn open_reference(alloc: Allocator, ver: []const u8) {
    var best_match: []const u8 = undefined;
    if (ver) |v| {
        best_match = v;
    } else {
        const dir_to_check = try std.process.getCwdAlloc(alloc);
        var overrides = try common.overrides.read_overrides(alloc, cp);
        defer overrides.deinit();

        best_match = try alloc.dupe(u8, (try overrides.active_version(dir_to_check)).ver);
    }

    const langref_path = try std.fs.path.join(alloc, &.{
        common.paths.CommonPaths.get_zigverm_root(),
        "installs/",
        try common.release_name(alloc, try common.Release.releasefromVersion(best_match)),
        "doc",
        "langref.html",
    });

    const main_exe = switch (builtin.os.tag) {
        .windows => "explorer",
        .macos => "open",
        else => "xdg-open",
    };

    var executable = std.ArrayList([]const u8).init(alloc);
    try executable.append(main_exe);
    try executable.append(langref_path);
    var child = std.process.Child.init(executable.items, alloc);
    try child.spawn();
}

fn show_info(alloc: Allocator, cp: CommonPaths) !void {
    std.debug.print("zigverm root:\t{s}\n\n", .{CommonPaths.get_zigverm_root()});
    var iter = cp.install_dir.iterate();

    const dir_to_check = try std.process.getCwdAlloc(alloc);
    var overrides = try common.overrides.read_overrides(alloc, cp);
    defer overrides.deinit();

    const active_version = (try overrides.active_version(dir_to_check));

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

fn override(alloc: Allocator, cp: CommonPaths, rel: Release, directory: []const u8) !void {
    var overrides = try common.overrides.read_overrides(alloc, cp);
    defer overrides.deinit();
    try overrides.addOverride(directory, rel.releaseName());
    try common.overrides.write_overrides(overrides, cp);
}

fn override_rm(alloc: Allocator, cp: CommonPaths, directory: []const u8) !void {
    if (streql(directory, "default")) {
        std.log.err("cannot remove the default override", .{});
        std.process.exit(1);
    }
    var overrides = try common.overrides.read_overrides(alloc, cp);
    defer overrides.deinit();
    _ = overrides.backing_map.orderedRemove(directory);
    try common.overrides.write_overrides(overrides, cp);
}

fn installed_versions(alloc: Allocator, cp: CommonPaths) ![][]const u8 {
    var iter = cp.install_dir.iterate();
    var versions = std.ArrayList([]const u8).init(alloc);
    while (try iter.next()) |i| {
        if (!utils.check_install_name(i.name)) continue;
        var components = std.mem.split(u8, i.name[4..], "-");
        _ = components.next();
        _ = components.next();
        const version = components.next() orelse unreachable;
        try versions.append(try alloc.dupe(u8, version));
    }
    return versions.items;
}

fn get_version_from_exe(alloc: Allocator, release_name: []const u8) !std.ArrayList(u8) {
    var executable = [2][]const u8{ undefined, "version" };
    executable[0] = try std.fs.path.join(alloc, &.{
        common.paths.CommonPaths.get_zigverm_root(),
        "installs/",
        release_name,
        "zig",
    });
    var version = std.ArrayList(u8).init(alloc);
    var stderr = std.ArrayList(u8).init(alloc);
    var child = std.process.Child.init(&executable, alloc);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;
    try child.spawn();
    try child.collectOutput(&version, &stderr, 256);
    _ = try child.wait();
    _ = version.pop();

    return version;
}

fn update_zig_installation(alloc: Allocator, cp: CommonPaths, version_possible: [][]const u8) !void {
    var versions: [][]const u8 = undefined;
    if (version_possible) |v| {
        versions = @constCast(&[1][]const u8{v});
    } else versions = try installed_versions(alloc, cp);

    var already_update = std.ArrayList([]const u8).init(alloc);
    var client = Client{ .allocator = alloc };
    defer client.deinit();
    const resp = try install.get_json_dslist(&client);
    const releases = try json.parseFromSliceLeaky(json.Value, alloc, resp.body[0..resp.length], .{});

    for (versions) |v| {
        var rel = try Release.releasefromVersion(v);
        const release_name = try common.release_name(alloc, rel);
        if (cp.install_dir.openDir(release_name, .{})) |_| {
            var to_update = false;
            if (rel.spec == common.ReleaseSpec.FullVersionSpec) {
                to_update = false;
            } else if (rel.spec == common.ReleaseSpec.Master) {
                const zig_version = try std.SemanticVersion.parse((try get_version_from_exe(alloc, release_name)).items);
                var next_master_release = try Release.releasefromVersion("master");
                try next_master_release.resolve(releases);
                if (zig_version.order(next_master_release.actual_version.?) != std.math.Order.eq) {
                    to_update = false;
                }
            } else if (rel.spec == common.ReleaseSpec.Stable) {
                const zig_version = try std.SemanticVersion.parse((try get_version_from_exe(alloc, release_name)).items);
                var next_stable_release = try Release.releasefromVersion("stable");
                try next_stable_release.resolve(releases);

                if (next_stable_release.actual_version.?.order(zig_version) == std.math.Order.gt) {
                    to_update = true;
                }
            } else {
                var zig_version = try std.SemanticVersion.parse((try get_version_from_exe(alloc, release_name)).items);
                var format_buf: [32]u8 = undefined;
                var format_buf_stream = std.io.fixedBufferStream(&format_buf);
                zig_version.patch += 1;
                try zig_version.format("", .{}, format_buf_stream.writer());
                to_update = releases.object.contains(format_buf_stream.getWritten());
                while (releases.object.contains(format_buf_stream.getWritten())) {
                    zig_version.patch += 1;
                    try format_buf_stream.seekTo(0);
                    try zig_version.format("", .{}, format_buf_stream.writer());
                }
            }
            if (to_update) {
                try install.install_release(alloc, &client, releases, &rel, cp);
            } else {
                try already_update.append(v);
            }
        } else |_| {
            try install.install_release(alloc, &client, releases, &rel, cp);
        }
    }
    if (already_update.items.len > 0) std.debug.print("\n", .{});

    for (already_update.items) |v| {
        std.debug.print("\t{s}    :    Up to date\n", .{v});
    }
}
