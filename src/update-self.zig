const std = @import("std");
const common = @import("common");
const install = @import("install.zig");
const builtin = @import("builtin");
const ZipArchive = @import("zip").read.ZipArchive;
const streql = common.streql;

const http = std.http;
const json = std.json;
const CommonPaths = common.paths.CommonPaths;
const Client = std.http.Client;
const File = std.fs.File;
const Allocator = std.mem.Allocator;
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

    fn createDownloadFile(self: *Self, cp1: CommonPaths) !void {
        self.file_handle = try cp1.download_dir.createFile(self.filename, .{ .read = true, .truncate = false });
        self.writer = self.file_handle.?.writer(&buf);
        self.file_size = @intCast(try self.file_handle.?.getEndPos());
    }

    fn deinit(self: *Self) !void {
        self.writer = null;
        self.file_handle.?.close();
        self.file_handle = null;
    }
};

pub fn update_self(alloc: Allocator, io: Io, cp: CommonPaths) !void {
    var client = Client{ .allocator = alloc, .io = io };
    defer client.deinit();

    std.log.info("getting latest index from github releases", .{});
    const parsed = try read_github_releases_data(alloc, io, &client);

    defer parsed.deinit();

    const version = parsed.value.object.get("name").?.string;
    const os = builtin.target.os.tag;
    const arch = builtin.target.cpu.arch;
    const dl_filename = try std.mem.join(alloc, "-", &.{ "zigverm", version[1..], @tagName(arch), @tagName(os) });
    const full_dl_filename = try std.mem.concat(alloc, u8, &.{ dl_filename, ".zip" });
    const assets = parsed.value.object.get("assets").?.array;

    var download_tarball = for (assets.items) |asset| {
        if (streql(full_dl_filename, asset.object.get("name").?.string)) {
            break DownloadTarball{
                .filename = full_dl_filename,
                .url = asset.object.get("browser_download_url").?.string,
                .actual_size = @intCast(asset.object.get("size").?.integer),
            };
        }
    } else {
        std.log.err("no updates available for the current platform", .{});
        std.process.exit(1);
    };

    try download_tarball.createDownloadFile(cp);
    defer download_tarball.deinit() catch {};
    if (download_tarball.file_size < download_tarball.actual_size)
        try install.download_tarball(alloc, io, &client, download_tarball.url, &download_tarball.writer.?, download_tarball.file_size, download_tarball.actual_size);
    try download_tarball.file_handle.?.seekTo(0);

    var buf: [4096]u8 = undefined;
    var src = download_tarball.file_handle.?.reader(io, &buf);

    var zipfile = try ZipArchive.openFromFileReader(alloc, &src);
    defer zipfile.close();

    const zigverm_path = try std.mem.join(alloc, "/", &.{ dl_filename, "zigverm" });
    const zig_path = try std.mem.join(alloc, "/", &.{ dl_filename, "zigverm" });
    try writeZipMember(zipfile, zigverm_path, cp);
    try writeZipMember(zipfile, zig_path, cp);

    std.log.info("zigverm updated successfully", .{});
    try cp.download_dir.deleteFile(full_dl_filename);
}

fn writeZipMember(zipfile: ZipArchive, path: []const u8, cp: CommonPaths) !void {
    const filename = std.fs.path.basename(path);
    const bin_dir = try cp.zigverm_root.openDir("bin/", .{});
    bin_dir.deleteFile(filename) catch |e| {
        if (e != error.FileNotFound) return e;
    };

    var buf: [4096]u8 = undefined;
    const file = try bin_dir.createFile(filename, .{ .truncate = true, .lock = .shared });
    var file_writer = file.writer(&buf);
    const intf = &file_writer.interface;
    defer file.close();

    var entry = zipfile.getFileByName(path).?;

    try entry.decompressWriter(intf);
    if (builtin.os.tag != .windows) {
        try file.chmod(0o755);
    }
}

fn read_github_releases_data(alloc: Allocator, io: Io, client: *Client) !json.Parsed(json.Value) {
    const uri = try std.Uri.parse("https://api.github.com/repos/AMythicDev/zigverm/releases/latest");
    var req = install.make_request(client, io, uri);
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
