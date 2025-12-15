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
    file_handle: ?std.fs.File = null,
    writer: ?std.fs.File.Writer = null,
    file_size: usize = 0,
    var buf: [4096]u8 = undefined;

    const Self = @This();

    fn createDownloadFile(self: *Self, download_dir: std.fs.Dir) !void {
        self.file_handle = try download_dir.createFile(self.filename, .{ .read = true, .truncate = false });
        self.writer = self.file_handle.?.writer(&buf);
        self.file_size = @intCast(try self.file_handle.?.getEndPos());
    }

    fn deinit(self: *Self) !void {
        self.writer = null;
        if (self.file_handle) |f| f.close();
        self.file_handle = null;
    }
};

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var threaded = Io.Threaded.init(allocator);
    const io = threaded.io();

    const zigverm_dir_path = std.process.getEnvVarOwned(allocator, "ZIGVERM_ROOT_DIR") catch |e1| blk: {
        if (e1 == error.EnvironmentVariableNotFound) {
            const env_var = if (builtin.os.tag == .windows) "USERPROFILE" else "HOME";
            const home_dir = std.process.getEnvVarOwned(allocator, env_var) catch |e2| {
                if (e2 != error.EnvironmentVariableNotFound) {
                    std.log.err("failed to determine home dir for current user", .{});
                    return {};
                } else {
                    return e2;
                }
            };
            break :blk try path.join(allocator, &.{ home_dir, ".zigverm" });
        } else return e1;
    };

    std.fs.makeDirAbsolute(zigverm_dir_path) catch |e| if (e != error.PathAlreadyExists) return e;

    var zigverm_dir = try std.fs.openDirAbsolute(zigverm_dir_path, .{});
    defer zigverm_dir.close();

    const DIRS_TO_CREATE = [3][]const u8{ "bin", "installs", "downloads" };

    for (DIRS_TO_CREATE) |dir| {
        zigverm_dir.makeDir(dir) catch |e| if (e != error.PathAlreadyExists) return e;
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

    var download_dir = try zigverm_dir.openDir("downloads", .{});
    defer download_dir.close();

    try tarball.createDownloadFile(download_dir);
    defer tarball.deinit() catch {};

    if (tarball.file_size < tarball.actual_size)
        try download_tarball(allocator, &client, io, tarball.url, &tarball.writer.?, tarball.file_size, tarball.actual_size);

    try tarball.file_handle.?.seekTo(0);

    var buf: [4096]u8 = undefined;
    var src = tarball.file_handle.?.reader(io, &buf);

    var zipfile = try ZipArchive.openFromFileReader(allocator, &src);
    defer zipfile.close();

    var bin_dir = try zigverm_dir.openDir("bin", .{});
    defer bin_dir.close();

    const path_in_zip = try std.mem.join(allocator, "/", &.{ dl_filename, "zigverm.exe" });

    if (zipfile.getFileByName(path_in_zip)) |*entry| {
        const out_filename = std.fs.path.basename(path_in_zip);
        var file = try bin_dir.createFile(out_filename, .{ .truncate = true });
        var fwriter = file.writer(&.{});
        const writer = &fwriter.interface;
        defer file.close();

        var entry_ptr = @constCast(entry);

        // Fix for error: expected 'std.io.Writer(std.fs.File,std.os.WriteError,std.fs.File.write)', found 'std.fs.File.Writer'
        // The type returned by file.writer() is usually correct.
        // Let's check entry.decompressWriter signature.
        try entry_ptr.decompressWriter(writer);
        std.log.info("Extracted {s} to bin/", .{out_filename});
    } else {
        std.log.err("Could not find {s} in archive", .{path_in_zip});
    }
}

pub fn download_tarball(alloc: std.mem.Allocator, client: *Client, io: Io, tb_url: []const u8, tb_writer: *std.fs.File.Writer, tarball_size: u64, total_size: usize) !void {
    std.log.info("Downloading {s}", .{tb_url});
    const tarball_uri = try std.Uri.parse(tb_url);

    var req = make_request(client, io, tarball_uri);
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
    var redir_buf: [1024]u8 = undefined;
    var response = try req.?.receiveHead(&redir_buf);

    var reader = response.reader(&.{});

    var buff: [1024]u8 = undefined;

    // Convert everything into f64 for less typing in calculating % download and download speed
    var dlnow = std.atomic.Value(f32).init(0);
    const total_size_d: f64 = @floatFromInt(total_size);
    const tarball_size_d: f64 = @floatFromInt(tarball_size);

    const progress_thread = try std.Thread.spawn(.{}, download_progress_bar, .{ io, &dlnow, tarball_size_d, total_size_d });
    const tbw_intf = &tb_writer.interface;
    while (tarball_size_d + dlnow.load(AtomicOrder.monotonic) <= total_size_d) {
        const len = try reader.readSliceShort(&buff);
        _ = try tbw_intf.write(buff[0..len]);
        _ = dlnow.fetchAdd(@floatFromInt(len), AtomicOrder.monotonic);

        if (len < buff.len) {
            break;
        }
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
        std.log.err("Failed fetching the install tarball. Exitting (1)...", .{});
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

pub fn download_progress_bar(io: Io, dlnow: *std.atomic.Value(f32), tarball_size: f64, total_size: f64) !void {
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

        io.sleep(.fromMilliseconds(500), .awake) catch {};
        downloaded = dlnow.load(AtomicOrder.monotonic);
    }
    try stderr_writer.print("\n", .{});
}
