const std = @import("std");
const http = std.http;
const Client = std.http.Client;
const json = std.json;
const builtin = @import("builtin");
const cli = @import("cli.zig");
const File = std.fs.File;
const Allocator = std.mem.Allocator;
const Sha256 = std.crypto.hash.sha2.Sha256;
const utils = @import("utils.zig");
const streql = utils.streql;

pub const Rel = union(enum) {
    Master,
    Stable: []const u8,
    Version: []const u8,

    const Self = @This();

    pub fn as_string(self: Self) []const u8 {
        switch (self) {
            Rel.Master => return "master",
            Rel.Version, Rel.Stable => |v| return v,
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

    fn releasefromVersion(alloc: Allocator, releases: json.Parsed(json.Value), version: []const u8) InstallError!Self {
        var rel: Rel = undefined;
        if (streql(version, "master")) {
            rel = Rel.Master;
        } else if (streql(version, "stable")) {
            rel = Rel{ .Stable = Rel.resolve_stable_release(alloc, releases).items };
        } else if (std.SemanticVersion.parse(version)) |_| {
            rel = Rel{ .Version = version };
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

const CommonDirs = struct {
    zigvm_root: std.fs.Dir,
    install_dir: std.fs.Dir,
    download_dir: std.fs.Dir,

    fn resolve_dirs(alloc: Allocator) !@This() {
        const zigvm_root = try std.fs.openDirAbsolute(try zigvm_dir(alloc), .{});
        return CommonDirs{
            .zigvm_root = zigvm_root,
            .install_dir = try zigvm_root.openDir("installs/", .{}),
            .download_dir = try zigvm_root.openDir("downloads/", .{}),
        };
    }

    fn zigvm_dir(alloc: Allocator) ![]const u8 {
        if (std.process.getEnvVarOwned(alloc, "ZIGVM_INSTALL_DIR")) |val| {
            return val;
        } else |_| {
            var buff = std.ArrayList(u8).init(alloc);
            try buff.appendSlice(try utils.home_dir(alloc));
            try buff.appendSlice("/.zigvm");
            return buff.items;
        }
    }
};

pub fn main() !void {
    var aa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = aa.allocator();

    const command = try cli.read_args(alloc);

    switch (command) {
        cli.Cli.Install => |version| {
            var client = Client{ .allocator = alloc };
            defer client.deinit();
            const resp = try get_json_dslist(&client);
            const releases = try json.parseFromSlice(json.Value, alloc, resp.body[0..resp.length], json.ParseOptions{});

            const dirs = try CommonDirs.resolve_dirs(alloc);

            const rel = try Rel.releasefromVersion(alloc, releases, version);
            try install_release(alloc, &client, releases, rel, dirs);
        },
        cli.Cli.Remove => |_| {},
    }
}

pub fn install_release(alloc: Allocator, client: *Client, releases: json.Parsed(json.Value), rel: Rel, dirs: CommonDirs) !void {
    var release: json.Value = releases.value.object.get(rel.as_string()).?;

    const target = release.object.get(utils.make_target_name()) orelse return InstallError.TargetNotAvailable;
    const tarball_url = target.object.get("tarball").?.string;

    const tarball_dw_filename = try utils.make_release_name(alloc, rel);
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
    const hash_matched = try check_hash(target.object.get("shasum").?.string[0..64], tarball_reader.reader());

    if (!hash_matched) {
        std.log.err("Hashes do match for downloaded tarball. Exitting (2)", .{});
        return error.BadChecksum;
    }
    try tarball_file.seekTo(0);

    std.log.info("Extracting {s}", .{tarball_dw_filename});
    try extract_xz(alloc, dirs.install_dir, tarball_reader.reader());

    try dirs.download_dir.deleteFile(tarball_dw_filename);
}

// fn remove_release() {
//
// }

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

fn check_hash(hashstr: *const [64]u8, reader: anytype) !bool {
    var buff: [1024]u8 = undefined;

    var hasher = Sha256.init(.{});

    while (true) {
        const len = try reader.read(&buff);
        if (len == 0) {
            break;
        }
        hasher.update(buff[0..len]);
    }
    var hash: [32]u8 = undefined;
    _ = try std.fmt.hexToBytes(&hash, hashstr);
    return std.mem.eql(u8, &hasher.finalResult(), &hash);
}

fn extract_xz(alloc: Allocator, dir: std.fs.Dir, reader: anytype) !void {
    var xz = try std.compress.xz.decompress(alloc, reader);
    try std.tar.pipeToFileSystem(dir, xz.reader(), .{});
}
