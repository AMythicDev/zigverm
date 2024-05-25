const std = @import("std");
const utils = @import("utils.zig");
const builtin = @import("builtin");
const Cli = @import("cli.zig").Cli;
const paths = @import("paths.zig");
const http = std.http;
const Client = std.http.Client;
const json = std.json;
const File = std.fs.File;
const Allocator = std.mem.Allocator;
const streql = utils.streql;
const CommonPaths = paths.CommonPaths;

pub const Rel = union(enum) {
    Master,
    Stable: ?[]const u8,
    Version: []const u8,

    const Self = @This();

    pub fn version(self: Self) []const u8 {
        switch (self) {
            Rel.Master => return "master",
            Rel.Stable => |ver| {
                if (ver) |v| {
                    return v;
                } else {
                    @panic("Rel.version() called when Rel.Stable is not resolved");
                }
            },
            Rel.Version => |v| return v,
        }
    }

    pub fn as_string(self: Self) []const u8 {
        switch (self) {
            Rel.Master => return "master",
            Rel.Version => |v| return v,
            Rel.Stable => return "stable",
        }
    }

    fn resolve_stable_release(alloc: Allocator, releases: json.Value) std.ArrayList(u8) {
        var buf = std.ArrayList(u8).init(alloc);
        var stable: ?std.SemanticVersion = null;
        for (releases.object.keys()) |release| {
            if (streql(release, "master")) continue;
            var r = std.SemanticVersion.parse(release) catch unreachable;
            if (stable == null) {
                stable = r;
                continue;
            }
            if (r.order(stable.?) == std.math.Order.gt) {
                stable = r;
            }
        }
        stable.?.format("", .{}, buf.writer()) catch unreachable;
        return buf;
    }

    pub fn releasefromVersion(alloc: Allocator, releases: ?json.Value, v: []const u8) InstallError!Self {
        var rel: Rel = undefined;
        if (streql(v, "master")) {
            rel = Rel.Master;
        } else if (streql(v, "stable")) {
            if (releases) |r| {
                rel = Rel{ .Stable = Rel.resolve_stable_release(alloc, r).items };
            } else {
                rel = Rel{ .Stable = null };
            }
        } else if (std.SemanticVersion.parse(v)) |_| {
            rel = Rel{ .Version = v };
        } else |_| {
            return InstallError.InvalidVersion;
        }
        return rel;
    }
};

const InstallError = error{
    ReleaseNotFound,
    InvalidVersion,
    TargetNotAvailable,
};

const JsonResponse = struct {
    body: [100 * 1024]u8,
    length: usize,
};

pub fn main() !void {
    var aa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = aa.allocator();

    const command = try Cli.read_args(alloc);

    const cp = try CommonPaths.resolve(alloc);
    defer cp.clone();

    switch (command) {
        Cli.install => |version| {
            var client = Client{ .allocator = alloc };
            defer client.deinit();

            if (!(try utils.check_not_installed(alloc, try Rel.releasefromVersion(alloc, null, version), cp))) {
                std.log.err("Version already installled. Quitting", .{});
                std.process.exit(0);
            }

            const resp = try get_json_dslist(&client);
            const releases = try json.parseFromSliceLeaky(json.Value, alloc, resp.body[0..resp.length], .{});
            const rel = try Rel.releasefromVersion(alloc, releases, version);

            try install_release(alloc, &client, releases, rel, cp);
        },
        Cli.remove => |version| {
            const rel = try Rel.releasefromVersion(alloc, null, version);
            try remove_release(alloc, rel, cp);
        },
        Cli.show => {
            try show_info(cp);
        },
        Cli.override => |oa| {
            var override_args = oa;
            const rel = try Rel.releasefromVersion(alloc, null, override_args.version);
            if (override_args.directory != null and !streql(override_args.directory.?, "default")) {
                override_args.directory = try std.fs.realpathAlloc(alloc, override_args.directory.?);
            }
            const directory = override_args.directory orelse try std.process.getCwdAlloc(alloc);
            try override(alloc, cp, rel, directory);
        },
    }
}

fn install_release(alloc: Allocator, client: *Client, releases: json.Value, rel: Rel, cp: CommonPaths) !void {
    var release: json.Value = releases.object.get(rel.version()).?;

    const target = release.object.get(utils.target_name()) orelse return InstallError.TargetNotAvailable;
    const tarball_url = target.object.get("tarball").?.string;
    const tarball_size = try std.fmt.parseInt(usize, target.object.get("size").?.string, 10);

    const tarball_dw_filename = try utils.dw_tarball_name(alloc, rel);

    var try_tarball_file = cp.download_dir.openFile(tarball_dw_filename, .{});

    if (try_tarball_file == File.OpenError.FileNotFound) {
        var tarball = try cp.download_dir.createFile(tarball_dw_filename, .{});
        defer tarball.close();

        var tarball_writer = std.io.bufferedWriter(tarball.writer());
        try download_tarball(
            client,
            tarball_url,
            &tarball_writer,
            tarball_size,
        );
        try_tarball_file = cp.download_dir.createFile(tarball_dw_filename, .{});
    } else {
        std.log.info("Found already existing tarball, using that", .{});
    }

    const tarball_file = try try_tarball_file;
    defer tarball_file.close();
    var tarball_reader = std.io.bufferedReader(tarball_file.reader());
    const hash_matched = try utils.check_hash(target.object.get("shasum").?.string[0..64], tarball_reader.reader());

    if (!hash_matched) {
        std.log.err("Hashes do match for downloaded tarball. Exitting", .{});
        return error.BadChecksum;
    }
    try tarball_file.seekTo(0);

    std.log.info("Extracting {s}", .{tarball_dw_filename});
    try utils.extract_xz(alloc, cp, rel, tarball_reader.reader());

    try cp.download_dir.deleteFile(tarball_dw_filename);
}

fn remove_release(alloc: Allocator, rel: Rel, cp: CommonPaths) !void {
    if ((try utils.check_not_installed(alloc, rel, cp))) {
        std.log.err("Version not installled. Quitting", .{});
        std.process.exit(0);
    }
    const release_dir = try utils.release_name(alloc, rel);
    try cp.install_dir.deleteTree(release_dir);
    std.log.err("Removed {s}", .{release_dir});
}

fn download_tarball(client: *Client, tb_url: []const u8, tb_writer: anytype, total_size: usize) !void {
    std.log.info("Downloading {s}", .{tb_url});
    const tarball_uri = try std.Uri.parse(tb_url);

    var req = make_request(client, tarball_uri);
    defer req.?.deinit();
    if (req == null) {
        std.log.err("Failed fetching the install tarball. Exitting (1)...", .{});
        std.process.exit(1);
    }

    try req.?.send();
    try req.?.wait();
    var reader = req.?.reader();

    var progress_bar: [52]u8 = undefined;
    progress_bar[0] = '[';
    @memset(progress_bar[1..50], ' ');
    progress_bar[51] = ']';

    var buff: [1024]u8 = undefined;
    var dlnow: usize = 0;
    var bars: u8 = 0;
    while (true) {
        const len = try reader.read(&buff);
        if (len == 0) {
            break;
        }
        _ = try tb_writer.write(buff[0..len]);

        dlnow += len;
        const pcnt_complete: u8 = @intCast((dlnow * 100 / total_size));
        var timer = try std.time.Timer.start();
        const newbars: u8 = pcnt_complete / 2;

        if (newbars > bars) {
            @memset(progress_bar[bars..newbars], '|');
            const dlspeed = @as(f64, @floatFromInt(dlnow)) / 1024 * 8 / @as(f64, @floatFromInt(timer.read()));
            std.debug.print("\r\t{s} {d}% {d:.1}kb/s", .{ progress_bar, pcnt_complete, dlspeed });
            bars = newbars;
        }
    }
    std.debug.print("\n", .{});
    try tb_writer.flush();
}

fn get_json_dslist(client: *Client) anyerror!JsonResponse {
    std.log.info("Fetching the latest index", .{});
    const uri = try std.Uri.parse("https://ziglang.org/download/index.json");

    var req = make_request(client, uri);
    defer req.?.deinit();
    if (req == null) {
        std.log.err("Failed fetching the index. Exitting (1)...", .{});
        std.process.exit(1);
    }

    try req.?.send();
    try req.?.wait();

    var json_buff: [1024 * 100]u8 = undefined;
    const bytes_read = try req.?.reader().readAll(&json_buff);

    return JsonResponse{ .body = json_buff, .length = bytes_read };
}

fn make_request(client: *Client, uri: std.Uri) ?Client.Request {
    var http_header_buff: [1024]u8 = undefined;
    for (0..5) |i| {
        const tryreq = client.open(
            http.Method.GET,
            uri,
            Client.RequestOptions{ .server_header_buffer = &http_header_buff },
        );
        if (tryreq) |r| {
            return r;
        } else |err| {
            std.log.warn("{}. Retrying again [{}/5]", .{ err, i + 1 });
            std.time.sleep(std.time.ns_per_ms * 500);
        }
    }
    return null;
}

fn show_info(cp: CommonPaths) !void {
    std.debug.print("zigvm root:\t{s}\n\n", .{CommonPaths.get_zigvm_root()});
    var iter = cp.install_dir.iterate();

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
    var file_bufreader = std.io.bufferedReader(cp.overrides.reader());
    var file_reader = file_bufreader.reader();
    var buff: [100]u8 = undefined;

    var overrides: std.StringArrayHashMap(json.Value) = undefined;

    // HACK: Here we are ensuring that the overrides.json file isn't empty, otherwise the json parsing will return an
    // error. Instead if the file is empty, we create ab enott StringArrayHashMap to hold our overrides.
    // Typically we would prefer the pread() function but its currently broken for Windows, hence we do hacky method
    // by checking if there bytes can be read and then resetting the file cursor back to 0.
    if (try file_reader.read(&buff) != 0) {
        try cp.overrides.seekTo(0);
        var json_reader = json.reader(alloc, file_reader);
        overrides = (try json.parseFromTokenSourceLeaky(json.Value, alloc, &json_reader, .{})).object;
    } else {
        overrides = std.StringArrayHashMap(json.Value).init(alloc);
    }

    try overrides.put(directory, json.Value{ .string = rel.as_string() });

    // NOTE: VERY IMPORTANT LINE FOR NOT SPAGHETTIFYING THE WHOLE FILE:
    // What we are effectively trying to do is truncate the file to zero length. For that we use the `setEndPos`
    // function. `setEndPos` resizes the file based on the current file cursor postion. It is sure that the file cursor
    // will be at the end of the file after all the above reading, hence we reset the cursor back to 0 so that there
    // isn't any weird byte writings at the beginning of the file.
    try cp.overrides.seekTo(0);
    try cp.overrides.setEndPos(0);
    var file_writer = std.io.bufferedWriter(cp.overrides.writer());
    try json.stringify(json.Value{ .object = overrides }, .{ .whitespace = .indent_4 }, file_writer.writer());
    _ = try file_writer.write("\n");
    try file_writer.flush();
}
