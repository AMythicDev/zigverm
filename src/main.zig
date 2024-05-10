const std = @import("std");
const http = std.http;
const Client = std.http.Client;
const json = std.json;
const builtin = @import("builtin");
const cli = @import("cli.zig");
const File = std.fs.File;
const Allocator = std.mem.Allocator;
const Sha256 = std.crypto.hash.sha2.Sha256;
const streql = @import("utils.zig").streql;

const Rel = union(enum) { Master, Stable, Version: []const u8 };

const InstallError = error{
    ReleaseNotFound,
    InvalidVersion,
    TargetNotAvailable,
    InvalidLength,
    CorruptInput,
    WrongChecksum,
    BadHeader,
    EndOfStreamWithNoError,
    Unsupported,
    UnexpectedEndOfStream,
    TarHeader,
    TarHeaderChksum,
    TarNumericValueNegative,
    TarNumericValueTooBig,
    TarInsufficientBuffer,
    StreamTooLong,
    PaxNullInKeyword,
    PaxInvalidAttributeEnd,
    PaxSizeAttrOverflow,
    PaxNullInValue,
    TarHeadersTooBig,
    TarUnsupportedHeader,
    LinkQuotaExceeded,
    ReadOnlyFileSystem,
    BadFileName,
    UnableToCreateSymLink,
} || std.Uri.ParseError || Client.RequestError || Client.Request.WaitError || File.OpenError || Client.Request.ReadError || File.WriteError || File.ReadError || File.SeekError || std.fs.Dir.DeleteFileError;

const JsonResponse = struct {
    body: [100 * 1024]u8,
    length: usize,
};

pub fn main() !void {
    var aa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = aa.allocator();

    const command = try cli.read_args(alloc);

    switch (command) {
        cli.Cli.Install => |rel| {
            var client = Client{ .allocator = alloc };
            defer client.deinit();
            const resp = try get_json_dslist(&client);
            const releases = try json.parseFromSlice(json.Value, alloc, resp.body[0..resp.length], json.ParseOptions{});

            if (streql(rel, "master")) {
                return try install_release(alloc, &client, releases, Rel.Master);
            } else if (streql(rel, "stable")) {
                return try install_release(alloc, &client, releases, Rel.Stable);
            } else if (std.SemanticVersion.parse(rel)) |_| {
                try install_release(alloc, &client, releases, Rel{ .Version = rel });
            } else |_| {
                return InstallError.InvalidVersion;
            }
        },
        cli.Cli.Remove => |_| {},
    }
}

pub fn install_release(alloc: Allocator, client: *Client, releases: json.Parsed(json.Value), rel: Rel) InstallError!void {
    var release: json.Value = undefined;
    var release_string: []const u8 = undefined;
    switch (rel) {
        Rel.Master => {
            release = releases.value.object.get("master").?;
            release_string = "master";
        },
        Rel.Version => |v| {
            release = releases.value.object.get(v) orelse return InstallError.ReleaseNotFound;
            release_string = v;
        },
        Rel.Stable => {
            release_string = find_stable_release(alloc, releases).items;
            release = releases.value.object.get(release_string).?;
        },
    }

    const os = builtin.target.os.tag;
    const arch = builtin.target.cpu.arch;

    const dw_target = @tagName(arch) ++ "-" ++ @tagName(os);
    const target = release.object.get(dw_target) orelse return InstallError.TargetNotAvailable;
    const tarball_url = target.object.get("tarball").?.string;

    const tarball_dw_filename = try std.mem.concat(alloc, u8, &[_][]const u8{ "zig-" ++ dw_target ++ "-", release_string, ".tar.xz.partial" });

    const cwd = std.fs.cwd();
    var try_tarball_file = cwd.openFile(tarball_dw_filename, .{});
    if (try_tarball_file == File.OpenError.FileNotFound) {
        var tarball = try cwd.createFile(tarball_dw_filename, .{});
        defer tarball.close();

        var tarball_writer = std.io.bufferedWriter(tarball.writer());
        try download_tarball(client, tarball_url, &tarball_writer);
        try_tarball_file = cwd.openFile(tarball_dw_filename, .{});
    } else {
        std.log.info("Found already existing tarball, using that", .{});
    }

    const tarball_file = try try_tarball_file;
    defer tarball_file.close();
    var tarball_reader = std.io.bufferedReader(tarball_file.reader());
    const hash_matched = try check_hash(target.object.get("shasum").?.string[0..64], tarball_reader.reader());

    if (!hash_matched) {
        std.log.err("Hashes do match for downloaded tarball. Exitting (2)", .{});
        std.process.exit(2);
    }
    try tarball_file.seekTo(0);

    std.log.info("Extracting {s}", .{tarball_dw_filename});
    try extract_xz(alloc, cwd, tarball_reader.reader());

    try cwd.deleteFile(tarball_dw_filename);
}

fn download_tarball(client: *Client, tb_url: []const u8, tb_writer: anytype) InstallError!void {
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

fn find_stable_release(alloc: Allocator, releases: json.Parsed(json.Value)) std.ArrayList(u8) {
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
