const std = @import("std");
const common = @import("common");
const utils = @import("utils.zig");
const builtin = @import("builtin");

const Allocator = std.mem.Allocator;
const Client = std.http.Client;
const json = std.json;
const Release = common.Release;
const paths = common.paths;
const CommonPaths = paths.CommonPaths;
const http = std.http;
const Sha256 = std.crypto.hash.sha2.Sha256;
const release_name = common.release_name;

const default_os = builtin.target.os.tag;
const default_arch = builtin.target.cpu.arch;

const JsonResponse = struct {
    body: [100 * 1024]u8,
    length: usize,
};

const InstallError = error{
    ReleaseNotFound,
    InvalidVersion,
    TargetNotAvailable,
};

pub fn install_release(alloc: Allocator, client: *Client, releases: json.Value, rel: *Release, cp: CommonPaths) !void {
    try rel.resolve(releases);

    const release: json.Value = releases.object.get(try rel.actualVersion(alloc)).?;
    const target = release.object.get(target_name()) orelse return InstallError.TargetNotAvailable;
    const tarball_url = target.object.get("tarball").?.string;
    const shasum = target.object.get("shasum").?.string[0..64];
    const total_size = try std.fmt.parseInt(usize, target.object.get("size").?.string, 10);

    const tarball_dw_filename = try dw_tarball_name(alloc, rel.*);

    var tarball = try get_correct_tarball(alloc, client, tarball_dw_filename, tarball_url, total_size, shasum, cp, 0);
    defer tarball.close();

    var tarball_reader = std.io.bufferedReader(tarball.reader());

    std.log.info("Extracting {s}", .{tarball_dw_filename});
    try cp.install_dir.deleteTree(try release_name(alloc, rel.*));
    try extract_xz(alloc, cp, rel.*, tarball_reader.reader());

    try cp.download_dir.deleteFile(tarball_dw_filename);
}

fn get_correct_tarball(alloc: Allocator, client: *Client, tarball_dw_filename: []const u8, tarball_url: []const u8, total_size: usize, shasum: *const [64]u8, cp: CommonPaths, tries: u8) !std.fs.File {
    const force_redownload = tries > 0;
    // IMPORTANT: To continue downloading if the file isn't completely downloaded AKA partial downloading, we
    // open the file with .truncate = false and then later move the file cursor to the end of the file using seekFromEnd().
    // This is basically Zig's equivalent to *open in append mode*.
    var tarball = try cp.download_dir.createFile(tarball_dw_filename, .{ .read = true, .truncate = force_redownload });
    const tarball_size = if (force_redownload) 0 else (try tarball.metadata()).size();

    if (tarball_size < total_size or force_redownload) {
        try tarball.seekTo(tarball_size);
        var tarball_writer = std.io.bufferedWriter(tarball.writer());
        try download_tarball(
            alloc,
            client,
            tarball_url,
            &tarball_writer,
            tarball_size,
            total_size,
        );
        try tarball.seekTo(0);
    } else {
        std.log.info("Found already existing tarball, using that", .{});
    }

    var tarball_reader = std.io.bufferedReader(tarball.reader());
    const hash_matched = try check_hash(shasum, tarball_reader.reader());

    if (!hash_matched) {
        if (tries < 3) {
            std.log.warn("Hashes do match for downloaded tarball. Retrying again...", .{});
            tarball = try get_correct_tarball(alloc, client, tarball_dw_filename, tarball_url, total_size, shasum, cp, tries + 1);
        } else {
            std.log.err("Hashes do match for downloaded tarball. Exitting", .{});
            return error.BadChecksum;
        }
    }
    try tarball.seekTo(0);
    return tarball;
}

pub fn download_tarball(alloc: Allocator, client: *Client, tb_url: []const u8, tb_writer: anytype, tarball_size: u64, total_size: usize) !void {
    std.log.info("Downloading {s}", .{tb_url});
    const tarball_uri = try std.Uri.parse(tb_url);

    var req = make_request(client, tarball_uri);
    defer req.?.deinit();
    if (req == null) {
        std.log.err("Failed fetching the install tarball. Exitting (1)...", .{});
        std.process.exit(1);
    }

    // Attach the Range header for partial downloads
    if (tarball_size > 0) {
        var size = std.ArrayList(u8).init(alloc);
        try size.appendSlice("bytes=");
        var size_writer = size.writer();
        try std.fmt.formatInt(tarball_size, 10, .lower, .{}, &size_writer);
        try size.append('-');
        req.?.extra_headers = &.{http.Header{ .name = "Range", .value = size.items }};
    }

    try req.?.send();
    try req.?.wait();
    var reader = req.?.reader();

    var progress_bar: [150]u8 = ("░" ** 50).*;
    var stderr_writer = std.io.getStdErr().writer();
    var buff: [1024]u8 = undefined;
    var bars: u8 = 0;

    // Convert everything into f64 for less typing in calculating % download and download speed
    var dlnow: f64 = @floatFromInt(tarball_size);
    const total_size_double: f64 = @floatFromInt(total_size);

    while (true) {
        const len = try reader.read(&buff);
        if (len == 0) {
            break;
        }
        _ = try tb_writer.write(buff[0..len]);

        dlnow += @floatFromInt(len);
        const pcnt_complete: u8 = @intFromFloat(dlnow * 100 / total_size_double);
        var timer = try std.time.Timer.start();
        const newbars: u8 = pcnt_complete / 2;
        for (bars..newbars) |i| {
            std.mem.copyForwards(u8, progress_bar[i * 3 .. i * 3 + 3], "█");
        }
        bars = newbars;
        const dlspeed = dlnow / 1024 * 8 / @as(f64, @floatFromInt(timer.read()));
        try stderr_writer.print("\r\t\x1b[33m{s}\x1b[0m{s} {d}% {d:.1}kb/s", .{ progress_bar[0 .. newbars * 3], progress_bar[newbars * 3 ..], pcnt_complete, dlspeed });
    }
    try stderr_writer.print("\n", .{});
    try tb_writer.flush();
}

pub fn get_json_dslist(client: *Client) anyerror!JsonResponse {
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

pub fn make_request(client: *Client, uri: std.Uri) ?Client.Request {
    var http_header_buff: [8192]u8 = undefined;
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

pub fn check_hash(hashstr: *const [64]u8, reader: anytype) !bool {
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

inline fn extract_xz(alloc: Allocator, dirs: CommonPaths, rel: Release, reader: anytype) !void {
    var xz = try std.compress.xz.decompress(alloc, reader);
    const release_dir = try dirs.install_dir.makeOpenPath(try release_name(alloc, rel), .{});
    try std.tar.pipeToFileSystem(release_dir, xz.reader(), .{ .strip_components = 1 });
}

pub fn target_name() []const u8 {
    return @tagName(default_arch) ++ "-" ++ @tagName(default_os);
}

pub fn dw_tarball_name(alloc: Allocator, rel: Release) ![]const u8 {
    const release_string = rel.releaseName();
    const dw_target = comptime target_name();
    return try std.mem.concat(alloc, u8, &[_][]const u8{ "zig-" ++ dw_target ++ "-", release_string, ".tar.xz.partial" });
}
