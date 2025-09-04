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
const AtomicOrder = std.builtin.AtomicOrder;
const time = std.time;
const File = std.fs.File;

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

    var buf: [4096]u8 = undefined;
    var tarball_reader = tarball.reader(&buf);
    const tbl_intf = &tarball_reader.interface;

    std.log.info("Extracting {s}", .{tarball_dw_filename});
    try cp.install_dir.deleteTree(try release_name(alloc, rel.*));
    try extract_xz(alloc, cp, rel.*, tbl_intf);

    try cp.download_dir.deleteFile(tarball_dw_filename);
}

fn get_correct_tarball(alloc: Allocator, client: *Client, tarball_dw_filename: []const u8, tarball_url: []const u8, total_size: usize, shasum: *const [64]u8, cp: CommonPaths, tries: u8) !std.fs.File {
    const force_redownload = tries > 0;
    // IMPORTANT: To continue downloading if the file isn't completely downloaded AKA partial downloading, we
    // open the file with .truncate = false and then later move the file cursor to the end of the file using seekFromEnd().
    // This is basically Zig's equivalent to *open in append mode*.
    var tarball = try cp.download_dir.createFile(tarball_dw_filename, .{ .read = true, .truncate = force_redownload });
    const tarball_size = if (force_redownload) 0 else try tarball.getEndPos();

    var buf: [4096]u8 = undefined;

    if (tarball_size < total_size or force_redownload) {
        try tarball.seekTo(tarball_size);
        var tarball_writer = tarball.writer(&buf);
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

    var tarball_reader = tarball.reader(&buf);
    const tbl_intf = &tarball_reader.interface;
    const hash_matched = try check_hash(shasum, tbl_intf);

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

pub fn download_tarball(alloc: Allocator, client: *Client, tb_url: []const u8, tb_writer: *std.fs.File.Writer, tarball_size: u64, total_size: usize) !void {
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
        var size: std.ArrayListUnmanaged(u8) = .empty;
        try size.print(alloc, "bytes={}-", .{tarball_size});
        req.?.extra_headers = &.{http.Header{ .name = "Range", .value = size.items }};
    }

    try req.?.sendBodiless();
    var response = try req.?.receiveHead(&.{});

    var reader = response.reader(&.{});

    var buff: [1024]u8 = undefined;

    // Convert everything into f64 for less typing in calculating % download and download speed
    var dlnow = std.atomic.Value(f32).init(0);
    const total_size_d: f64 = @floatFromInt(total_size);
    const tarball_size_d: f64 = @floatFromInt(tarball_size);

    const progress_thread = try std.Thread.spawn(.{}, download_progress_bar, .{ &dlnow, tarball_size_d, total_size_d });
    const tbw_intf = &tb_writer.interface;
    while (tarball_size_d + dlnow.load(AtomicOrder.monotonic) <= total_size_d) {
        const len = try reader.readSliceShort(&buff);
        if (len == 0) {
            break;
        }
        _ = try tbw_intf.write(buff[0..len]);

        _ = dlnow.fetchAdd(@floatFromInt(len), AtomicOrder.monotonic);
    }
    progress_thread.join();
    try tb_writer.end();
}

pub fn download_progress_bar(dlnow: *std.atomic.Value(f32), tarball_size: f64, total_size: f64) !void {
    const stderr = std.fs.File.stderr();
    var stderrw = std.fs.File.Writer.init(stderr, &.{});
    const stderr_writer = &stderrw.interface;
    var progress_bar: [150]u8 = ("░" ** 50).*;
    var bars: u8 = 0;
    var timer = try time.Timer.start();
    var downloaded = dlnow.load(AtomicOrder.monotonic);

    while (true) {
        const pcnt_complete: u8 = @intFromFloat((downloaded + tarball_size) * 100 / total_size);
        const newbars: u8 = pcnt_complete / 2;
        for (bars..newbars) |i| {
            std.mem.copyForwards(u8, progress_bar[i * 3 .. i * 3 + 3], "█");
        }
        bars = newbars;
        const speed = downloaded / 1024 / @as(f64, @floatFromInt(timer.read() / time.ns_per_s));
        try stderr_writer.print("\x1b[G\x1b[0K\t\x1b[33m{s}\x1b[0m{s} {d}% {d:.1}KB/s", .{ progress_bar[0 .. newbars * 3], progress_bar[newbars * 3 ..], pcnt_complete, speed });

        if (downloaded + tarball_size >= total_size) break;

        std.Thread.sleep(500 * time.ns_per_ms);
        downloaded = dlnow.load(AtomicOrder.monotonic);
    }
    try stderr_writer.print("\n", .{});
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

    try req.?.sendBodiless();
    var response = try req.?.receiveHead(&.{});

    var json_buff: [1024 * 100]u8 = undefined;
    const res_r = response.reader(&.{});
    const bytes_read = try res_r.readSliceShort(&json_buff);

    return JsonResponse{ .body = json_buff, .length = bytes_read };
}

pub fn make_request(client: *Client, uri: std.Uri) ?Client.Request {
    // TODO: REMOVE THIS IF UNUSED
    var http_header_buff: [8192]u8 = undefined;
    _ = &http_header_buff;
    for (0..5) |i| {
        const tryreq = client.request(http.Method.GET, uri, .{});
        if (tryreq) |r| {
            return r;
        } else |err| {
            std.log.warn("{}. Retrying again [{}/5]", .{ err, i + 1 });
            std.Thread.sleep(std.time.ns_per_ms * 500);
        }
    }
    return null;
}

pub fn check_hash(hashstr: *const [64]u8, reader: *std.Io.Reader) !bool {
    var buff: [1024]u8 = undefined;

    var hasher = Sha256.init(.{});

    while (true) {
        const len = try reader.readSliceShort(&buff);
        if (len == 0) {
            break;
        }
        hasher.update(buff[0..len]);
    }
    var hash: [32]u8 = undefined;
    _ = try std.fmt.hexToBytes(&hash, hashstr);
    return std.mem.eql(u8, &hasher.finalResult(), &hash);
}

inline fn extract_xz(alloc: Allocator, dirs: CommonPaths, rel: Release, reader: *std.Io.Reader) !void {
    // HACK: Use the older interface until Zig upgrades this
    const r = reader.adaptToOldInterface();
    var xz = try std.compress.xz.decompress(alloc, r);
    const release_dir = try dirs.install_dir.makeOpenPath(try release_name(alloc, rel), .{});
    var adpt = xz.reader().adaptToNewApi(&.{});
    const intf = &adpt.new_interface;
    try std.tar.pipeToFileSystem(release_dir, intf, .{ .strip_components = 1 });
}

pub fn target_name() []const u8 {
    return @tagName(default_arch) ++ "-" ++ @tagName(default_os);
}

pub fn dw_tarball_name(alloc: Allocator, rel: Release) ![]const u8 {
    const release_string = rel.releaseName();
    const dw_target = comptime target_name();
    return try std.mem.concat(alloc, u8, &[_][]const u8{ "zig-" ++ dw_target ++ "-", release_string, ".tar.xz.partial" });
}
