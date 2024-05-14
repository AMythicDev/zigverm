const std = @import("std");
const http = std.http;
const Client = std.http.Client;
const json = std.json;
const builtin = @import("builtin");
const cli = @import("cli.zig");
const File = std.fs.File;
const Allocator = std.mem.Allocator;
const utils = @import("utils.zig");
const streql = utils.streql;
const CommonDirs = utils.CommonDirs;

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
                    @panic("Rel.version*() called when Rel.Stable is not resolved");
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

    fn resolve_stable_release(alloc: Allocator, releases: json.Parsed(json.Value)) std.ArrayList(u8) {
        var buf = std.ArrayList(u8).init(alloc);
        var stable: ?std.SemanticVersion = null;
        for (releases.value.object.keys()) |release| {
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

    pub fn releasefromVersion(alloc: Allocator, releases: ?json.Parsed(json.Value), v: []const u8) InstallError!Self {
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

    const command = try cli.read_args(alloc);

    switch (command) {
        cli.Cli.install => |version| {
            var client = Client{ .allocator = alloc };
            defer client.deinit();

            const dirs = try CommonDirs.resolve_dirs(alloc);

            if (!(try utils.check_not_installed(alloc, try Rel.releasefromVersion(alloc, null, version), dirs))) {
                std.log.err("Version already installled. Quitting", .{});
                std.process.exit(0);
            }

            const resp = try get_json_dslist(&client);
            const releases = try json.parseFromSlice(json.Value, alloc, resp.body[0..resp.length], json.ParseOptions{});
            const rel = try Rel.releasefromVersion(alloc, releases, version);

            try install_release(alloc, &client, releases, rel, dirs);
        },
        cli.Cli.remove => |version| {
            const dirs = try CommonDirs.resolve_dirs(alloc);
            const rel = try Rel.releasefromVersion(alloc, null, version);
            try remove_release(alloc, rel, dirs);
        },
        cli.Cli.show => {
            const dirs = try CommonDirs.resolve_dirs(alloc);
            try show_info(dirs);
        },
    }
}

pub fn install_release(alloc: Allocator, client: *Client, releases: json.Parsed(json.Value), rel: Rel, dirs: CommonDirs) !void {
    var release: json.Value = releases.value.object.get(rel.version()).?;

    const target = release.object.get(utils.target_name()) orelse return InstallError.TargetNotAvailable;
    const tarball_url = target.object.get("tarball").?.string;

    const tarball_dw_filename = try utils.dw_tarball_name(alloc, rel);
    var try_tarball_file = dirs.download_dir.openFile(tarball_dw_filename, .{});

    if (try_tarball_file == File.OpenError.FileNotFound) {
        var tarball = try dirs.download_dir.createFile(tarball_dw_filename, .{});
        defer tarball.close();

        var tarball_writer = std.io.bufferedWriter(tarball.writer());
        try download_tarball(client, tarball_url, &tarball_writer);
        try_tarball_file = dirs.download_dir.openFile(tarball_dw_filename, .{});
    } else {
        std.log.info("Found already existing tarball, using that", .{});
    }

    const tarball_file = try try_tarball_file;
    defer tarball_file.close();
    var tarball_reader = std.io.bufferedReader(tarball_file.reader());
    const hash_matched = try utils.check_hash(target.object.get("shasum").?.string[0..64], tarball_reader.reader());

    if (!hash_matched) {
        std.log.err("Hashes do match for downloaded tarball. Exitting (2)", .{});
        return error.BadChecksum;
    }
    try tarball_file.seekTo(0);

    std.log.info("Extracting {s}", .{tarball_dw_filename});
    try utils.extract_xz(alloc, dirs, rel, tarball_reader.reader());

    try dirs.download_dir.deleteFile(tarball_dw_filename);
}

fn remove_release(alloc: Allocator, rel: Rel, dirs: CommonDirs) !void {
    if ((try utils.check_not_installed(alloc, rel, dirs))) {
        std.log.err("Version not installled. Quitting", .{});
        std.process.exit(0);
    }
    const release_dir = try utils.release_name(alloc, rel);
    try dirs.install_dir.deleteTree(release_dir);
    std.log.err("Removed {s}", .{release_dir});
}

fn download_tarball(client: *Client, tb_url: []const u8, tb_writer: anytype) !void {
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

    var buff: [1024]u8 = undefined;
    while (true) {
        const len = try reader.read(&buff);
        if (len == 0) {
            break;
        }
        _ = try tb_writer.write(buff[0..len]);
    }
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

fn show_info(dirs: CommonDirs) !void {
    std.debug.print("zigvm root:\t{s}\n\n", .{CommonDirs.get_zigvm_root()});
    var iter = dirs.install_dir.iterate();

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
