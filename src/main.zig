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

pub const Version = "0.2.0";

pub fn main() !void {
    var aa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = aa.allocator();

    const command = try Cli.read_args(alloc);

    var cp = try CommonPaths.resolve(alloc);
    defer cp.close();

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
        Cli.show => try show_info(alloc, cp),
        Cli.std => |ver| {
            var best_match: []const u8 = undefined;
            if (ver) |v| {
                best_match = v;
            } else {
                const dir_to_check = try std.process.getCwdAlloc(alloc);
                var overrides = try common.overrides.read_overrides(alloc, cp);
                defer overrides.deinit();

                best_match = (try overrides.active_version(dir_to_check)).ver;
            }

            const zig_path = try std.fs.path.join(alloc, &.{
                common.paths.CommonPaths.get_zigvm_root(),
                "installs/",
                try common.release_name(alloc, try common.Rel.releasefromVersion(best_match)),
                "zig",
            });

            var executable = std.ArrayList([]const u8).init(alloc);
            try executable.append(zig_path);
            try executable.append("std");
            var child = std.process.Child.init(executable.items, alloc);
            const term = try child.spawnAndWait();
            std.process.exit(term.Exited);
        },
        Cli.reference => |ver| {
            var best_match: []const u8 = undefined;
            if (ver) |v| {
                best_match = v;
            } else {
                const dir_to_check = try std.process.getCwdAlloc(alloc);
                var overrides = try common.overrides.read_overrides(alloc, cp);
                defer overrides.deinit();

                best_match = (try overrides.active_version(dir_to_check)).ver;
            }

            const langref_path = try std.fs.path.join(alloc, &.{
                common.paths.CommonPaths.get_zigvm_root(),
                "installs/",
                try common.release_name(alloc, try common.Rel.releasefromVersion(best_match)),
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
        Cli.update => |version_possible| {
            var versions: [][]const u8 = undefined;
            var check_installed = false;
            if (version_possible) |v| {
                versions = @constCast(&[1][]const u8{v});
                check_installed = true;
            } else versions = try installed_versions(alloc, cp);

            var uptodate = std.ArrayList([]const u8).init(alloc);
            var client = Client{ .allocator = alloc };
            defer client.deinit();
            const resp = try install.get_json_dslist(&client);
            const releases = try json.parseFromSliceLeaky(json.Value, alloc, resp.body[0..resp.length], .{});

            for (versions) |v| {
                var rel = try Rel.releasefromVersion(v);
                if (check_installed and try utils.check_not_installed(alloc, rel, cp)) {
                    try install.install_release(alloc, &client, releases, &rel, cp);
                    return;
                }
                if (rel.release == common.ReleaseSpec.FullVersionSpec) {
                    try uptodate.append(v);
                    continue;
                }
                try install.install_release(alloc, &client, releases, &rel, cp);
            }

            std.debug.print("\n", .{});
            for (uptodate.items) |v| {
                std.debug.print("\t{s}    :    Up to date\n", .{v});
            }
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

fn override(alloc: Allocator, cp: CommonPaths, rel: Rel, directory: []const u8) !void {
    var overrides = try common.overrides.read_overrides(alloc, cp);
    defer overrides.deinit();
    try overrides.backing_map.put(directory, rel.releaseName());
    try common.overrides.write_overrides(overrides, cp);
}

fn override_rm(alloc: Allocator, cp: CommonPaths, directory: []const u8) !void {
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
