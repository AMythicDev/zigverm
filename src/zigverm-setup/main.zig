const std = @import("std");
const path = std.fs.path;
const common = @import("common");
const http = std.http;
const json = std.json;
const builtin = @import("builtin");
const ZipArchive = @import("zip").read.ZipArchive;
const streql = common.streql;
const Client = std.http.Client;
const AtomicOrder = std.builtin.AtomicOrder;
const time = std.time;
const Io = std.Io;

const DownloadTarball = struct {
    filename: []const u8,
    url: []const u8,
    actual_size: usize,
    file_handle: ?std.Io.File = null,
    writer: ?std.Io.File.Writer = null,
    file_size: usize = 0,
    var buf: [4096]u8 = undefined;

    const Self = @This();

    fn createDownloadFile(self: *Self, io: Io, download_dir: std.Io.Dir) !void {
        self.file_handle = try download_dir.createFile(io, self.filename, .{ .read = true, .truncate = false });
        self.writer = self.file_handle.?.writer(io, &buf);
        self.file_size = @intCast(try self.file_handle.?.length(io));
        self.writer.?.pos = self.file_size;
    }

    fn deinit(self: *Self, io: Io) !void {
        self.writer = null;
        if (self.file_handle) |f| f.close(io);
        self.file_handle = null;
    }
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.arena.allocator();

    const zigverm_dir_path = init.environ_map.get("ZIGVERM_ROOT_DIR") orelse blk: {
        const env_var = if (builtin.os.tag == .windows) "USERPROFILE" else "HOME";
        const home_dir = init.environ_map.get(env_var) orelse {
            std.log.err("failed to determine home dir for current user", .{});
            return {};
        };
        break :blk try path.join(allocator, &.{ home_dir, ".zigverm" });
    };

    std.Io.Dir.createDirAbsolute(io, zigverm_dir_path, .default_dir) catch |e| if (e != error.PathAlreadyExists) return e;

    var zigverm_dir = try std.Io.Dir.openDirAbsolute(io, zigverm_dir_path, .{});
    defer zigverm_dir.close(io);

    const DIRS_TO_CREATE = [3][]const u8{ "bin", "installs", "downloads" };

    for (DIRS_TO_CREATE) |dir| {
        zigverm_dir.createDir(io, dir, .default_dir) catch |e| if (e != error.PathAlreadyExists) return e;
    }

    // Fetch and Install Logic
    var client = Client{ .allocator = allocator, .io = io };
    defer client.deinit();

    std.log.info("getting latest index from github releases", .{});
    const parsed = try read_github_releases_data(allocator, io, &client);
    defer parsed.deinit();

    const version = parsed.value.object.get("name").?.string;
    const arch = builtin.target.cpu.arch;

    const dl_filename = try std.mem.join(allocator, "-", &.{ "zigverm", version[1..], @tagName(arch), "windows" });
    const full_dl_filename = try std.mem.concat(allocator, u8, &.{ dl_filename, ".zip" });
    const assets = parsed.value.object.get("assets").?.array;

    var tarball = for (assets.items) |asset| {
        if (streql(full_dl_filename, asset.object.get("name").?.string)) {
            break DownloadTarball{
                .filename = full_dl_filename,
                .url = asset.object.get("browser_download_url").?.string,
                .actual_size = @intCast(asset.object.get("size").?.integer),
            };
        }
    } else {
        std.log.err("This installer only supports Windows", .{});
        return;
    };

    var download_dir = try zigverm_dir.openDir(io, "downloads", .{});
    defer download_dir.close(io);

    try tarball.createDownloadFile(io, download_dir);
    defer tarball.deinit(io) catch {};

    if (tarball.file_size < tarball.actual_size)
        try download_tarball(allocator, &client, io, tarball.url, &tarball.writer.?, tarball.file_size, tarball.actual_size);

    var buf: [4096]u8 = undefined;
    var src = tarball.file_handle.?.reader(io, &buf);
    try src.seekTo(0);

    var zipfile = try ZipArchive.openFromFileReader(allocator, &src);
    defer zipfile.close();

    var bin_dir = try zigverm_dir.openDir(io, "bin", .{});
    defer bin_dir.close(io);

    const zigverm_path = try std.mem.join(allocator, "/", &.{ dl_filename, "zigverm.exe" });
    const zig_path = try std.mem.join(allocator, "/", &.{ dl_filename, "zig.exe" });

    try writeFilesFromZip(io, bin_dir, zipfile, zigverm_path);
    try writeFilesFromZip(io, bin_dir, zipfile, zig_path);

    std.log.info("Installed zigverm successfully", .{});

    std.log.info("Installing latest stable zig version...", .{});
    const installed_binary = try path.join(allocator, &.{ zigverm_dir_path, "bin", "zigverm.exe" });

    var child = try std.process.spawn(io, .{ .argv = &.{ installed_binary, "install", "stable" } });
    _ = try child.wait(io);
}

fn writeFilesFromZip(io: Io, bin_dir: std.Io.Dir, zipFile: ZipArchive, filename: []const u8) !void {
    const entry = zipFile.getFileByName(filename) orelse unreachable;
    const out_filename = path.basename(filename);
    var file = try bin_dir.createFile(io, out_filename, .{ .truncate = true });
    defer file.close(io);
    var fwriter = file.writer(io, &.{});
    const writer = &fwriter.interface;
    var entry_ptr = @constCast(&entry);
    try entry_ptr.decompressWriter(writer);
    if (builtin.os.tag != .windows) {
        try file.setPermissions(io, std.Io.File.Permissions.fromMode(0o755));
    }
}

fn download_tarball(
    alloc: std.mem.Allocator,
    client: *Client,
    io: Io,
    tb_url: []const u8,
    tb_writer: *std.Io.File.Writer,
    tarball_size: u64,
    total_size: usize,
) !void {
    std.log.info("Downloading {s}", .{tb_url});
    const tarball_uri = try std.Uri.parse(tb_url);

    var req = make_request(client, io, tarball_uri);
    defer req.?.deinit();
    if (req == null) {
        std.log.err("Failed fetching the install tarball. Exiting (1)...", .{});
        std.process.exit(1);
    }

    // Attach the Range header for partial downloads
    if (tarball_size > 0) {
        var size: std.ArrayListUnmanaged(u8) = .empty;
        try size.print(alloc, "bytes={}-", .{tarball_size});
        req.?.extra_headers = &.{http.Header{ .name = "Range", .value = size.items }};
    }

    try req.?.sendBodiless();
    var redir_buf: [1024]u8 = undefined;
    var response = try req.?.receiveHead(&redir_buf);

    if (response.head.status.class() != .success) {
        std.log.err("HTTP error: {s} ({d})", .{ response.head.reason, @intFromEnum(response.head.status) });
        return error.HttpError;
    }

    var active_tarball_size = tarball_size;
    if (tarball_size > 0 and response.head.status != .partial_content) {
        active_tarball_size = 0;
        try tb_writer.seekTo(0);
    }

    var reader = response.reader(&.{});

    var buff: [1024]u8 = undefined;

    var dlnow = std.atomic.Value(usize).init(0);
    const tarball_size_u: usize = @intCast(active_tarball_size);

    const progress_thread = try std.Thread.spawn(.{}, download_progress_bar, .{ io, &dlnow, tarball_size_u, total_size });
    const tbw_intf = &tb_writer.interface;
    while (true) {
        const len = try reader.readSliceShort(&buff);
        try tbw_intf.writeAll(buff[0..len]);
        _ = dlnow.fetchAdd(len, AtomicOrder.monotonic);
        if (len < buff.len) break;
    }
    progress_thread.join();
    try tb_writer.end();
}

pub fn make_request(client: *Client, io: Io, uri: std.Uri) ?Client.Request {
    for (0..5) |i| {
        const tryreq = client.request(http.Method.GET, uri, .{});
        if (tryreq) |r| {
            return r;
        } else |err| {
            std.log.warn("{}. Retrying again [{}/5]", .{ err, i + 1 });
            io.sleep(.fromMilliseconds(500), .awake) catch {};
        }
    }
    return null;
}

fn read_github_releases_data(alloc: std.mem.Allocator, io: Io, client: *Client) !json.Parsed(json.Value) {
    const uri = try std.Uri.parse("https://api.github.com/repos/AMythicDev/zigverm/releases/latest");
    var req = make_request(client, io, uri);
    defer req.?.deinit();

    if (req == null) {
        std.log.err("Failed fetching the install tarball. Exiting (1)...", .{});
        std.process.exit(1);
    }
    req.?.extra_headers = &.{ http.Header{ .name = "Accept", .value = "application/vnd.github+json" }, http.Header{ .name = "X-GitHub-Api-Version", .value = "2022-11-28" } };
    try req.?.sendBodiless();

    var tbuf: [1024]u8 = undefined;
    var dbuf: [std.compress.flate.max_window_len]u8 = undefined;
    var decomp = http.Decompress{ .none = undefined };
    var resp = try req.?.receiveHead(&.{});

    const res_r = resp.readerDecompressing(&tbuf, &decomp, &dbuf);

    var json_reader = json.Reader.init(alloc, res_r);
    return try json.parseFromTokenSource(json.Value, alloc, &json_reader, .{});
}

pub fn download_progress_bar(io: Io, dlnow: *std.atomic.Value(usize), tarball_size: usize, total_size: usize) !void {
    const stderr = std.Io.File.stderr();
    var stderrw = std.Io.File.Writer.init(stderr, io, &.{});
    const stderr_writer = &stderrw.interface;
    var progress_bar: [150]u8 = ("░" ** 50).*;
    var bars: u8 = 0;

    const clock = std.Io.Clock.real;
    const start = clock.now(io);

    var downloaded = dlnow.load(AtomicOrder.monotonic);

    while (true) {
        const pcnt_complete: u8 = @intCast((downloaded + tarball_size) * 100 / total_size);
        const newbars: u8 = pcnt_complete / 2;
        for (bars..newbars) |i| {
            std.mem.copyForwards(u8, progress_bar[i * 3 .. i * 3 + 3], "█");
        }
        bars = newbars;
        const time_passed: f64 = @floatFromInt(start.untilNow(io, clock).toSeconds());
        const speed = @as(f64, @floatFromInt(downloaded)) / 1024.0 / time_passed;
        try stderr_writer.print("\x1b[G\x1b[0K\t\x1b[33m{s}\x1b[0m{s} {d}% {d:.1}KB/s", .{ progress_bar[0 .. newbars * 3], progress_bar[newbars * 3 ..], pcnt_complete, speed });

        if (downloaded + tarball_size >= total_size) break;

        io.sleep(.fromMilliseconds(500), .awake) catch {};
        downloaded = dlnow.load(AtomicOrder.monotonic);
    }
    try stderr_writer.print("\n", .{});
}
