const std = @import("std");
const common = @import("common");
const install = @import("install.zig");
const builtin = @import("builtin");
const streql = common.streql;

const http = std.http;
const json = std.json;
const CommonPaths = common.paths.CommonPaths;
const Client = std.http.Client;
const File = std.fs.File;
const BufferedReader = std.io.BufferedReader;
const BufferedWriter = std.io.BufferedWriter;
const Allocator = std.mem.Allocator;
const ZipArchive = @import("zip").read.ZipArchive;

const DownloadTarball = struct {
    filename: []const u8,
    url: []const u8,
    actual_size: usize,

    file_handle: ?std.fs.File = null,
    writer: ?BufferedWriter(4096, std.fs.File.Writer) = null,
    file_size: usize = 0,

    const Self = @This();

    fn createDownloadFile(self: *Self, cp1: CommonPaths) !void {
        self.file_handle = try cp1.download_dir.createFile(self.filename, .{ .read = true, .truncate = false });
        self.writer = std.io.bufferedWriter(self.file_handle.?.writer());
        self.file_size = (try self.file_handle.?.metadata()).size();
    }

    fn deinit(self: *Self) !void {
        self.writer = null;
        self.file_handle.?.close();
        self.file_handle = null;
    }
};

pub fn update_self(alloc: Allocator, cp: CommonPaths) !void {
    var client = Client{ .allocator = alloc };
    defer client.deinit();

    std.log.info("getting latest index from github releases", .{});
    const parsed = try read_github_releases_data(alloc, &client);

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
    if (download_tarball.file_size < download_tarball.actual_size)
        try install.download_tarball(alloc, &client, download_tarball.url, &download_tarball.writer.?, download_tarball.file_size, download_tarball.actual_size);
    try download_tarball.file_handle.?.seekTo(0);
    const bin_dir = try cp.zigverm_root.openDir("bin/", .{});

    const zipfile = try ZipArchive.openFromStreamSource(alloc, @constCast(&std.io.StreamSource{ .file = download_tarball.file_handle.? }));

    var m_iter = zipfile.members.iterator();
    while (m_iter.next()) |i| {
        var entry = i.value_ptr.*;
        if (entry.is_dir) continue;

        const filename = std.fs.path.basename(i.key_ptr.*);
        const file = try bin_dir.createFile(filename, .{ .truncate = true, .lock = .shared });
        var file_writer = std.io.bufferedWriter(file.writer());
        defer file.close();

        _ = try entry.decompressWriter(&file_writer.writer());
    }
    std.debug.print("zigverm updated successfully", .{});
}

fn read_github_releases_data(alloc: Allocator, client: *Client) !json.Parsed(json.Value) {
    const uri = try std.Uri.parse("https://api.github.com/repos/AMythicDev/zigverm/releases/latest");
    var req = install.make_request(client, uri);
    defer req.?.deinit();

    if (req == null) {
        std.log.err("Failed fetching the install tarball. Exitting (1)...", .{});
        std.process.exit(1);
    }
    req.?.extra_headers = &.{ http.Header{ .name = "Accept", .value = "application/vnd.github+json" }, http.Header{ .name = "X-GitHub-Api-Version", .value = "2022-11-28" } };
    try req.?.send();
    try req.?.wait();
    var json_reader = json.reader(alloc, req.?.reader());
    return try json.parseFromTokenSource(json.Value, alloc, &json_reader, .{});
}
