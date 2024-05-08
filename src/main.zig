const std = @import("std");
const http = std.http;
const Client = std.http.Client;
const json = std.json;
const builtin = @import("builtin");
const cli = @import("cli.zig");
const File = std.fs.File;
const Allocator = std.mem.Allocator;

const Rel = union(enum) { Master, Version: []const u8 };

const InstallError = error{ ReleaseNotFound, InvalidVersion, TargetNotAvailable, InvalidLength } || std.Uri.ParseError || Client.RequestError || Client.Request.WaitError || std.fs.File.OpenError || Client.Request.ReadError || std.fs.File.WriteError || std.fs.File.ReadError;

const JsonResponse = struct {
    body: [100 * 1024]u8,
    length: usize,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();

    const command = try cli.read_args(alloc);

    switch (command) {
        cli.Cli.Install => |rel| {
            defer alloc.free(rel);
            var client = Client{ .allocator = alloc };
            defer client.deinit();
            const resp = try get_json_dslist(&client);
            const releases = try json.parseFromSlice(json.Value, alloc, resp.body[0..resp.length], json.ParseOptions{});
            defer releases.deinit();

            if (std.mem.eql(u8, rel, "master")) {
                return try install_release(alloc, &client, releases, Rel.Master);
            } else if (std.SemanticVersion.parse(rel)) |_| {
                try install_release(alloc, &client, releases, Rel{ .Version = rel });
            } else |_| {
                return InstallError.InvalidVersion;
            }
        },
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
    }

    const os = builtin.target.os.tag;
    const arch = builtin.target.cpu.arch;

    const dw_target = @tagName(arch) ++ "-" ++ @tagName(os);
    const target = release.object.get(dw_target) orelse return InstallError.TargetNotAvailable;
    const tarball_url = target.object.get("tarball").?.string;

    const tarball_dw_filename = try std.mem.concat(alloc, u8, &[_][]const u8{ "zig-" ++ dw_target ++ "-", release_string, ".tar.xz.partial" });

    const cwd = std.fs.cwd();
    var tarball_file = cwd.openFile(tarball_dw_filename, .{});
    if (tarball_file == File.OpenError.FileNotFound) {
        const tarball = try cwd.createFile(tarball_dw_filename, .{});
        defer tarball.close();
        const tarball_writer = tarball.writer();
        try download_tarball(client, tarball_url, tarball_writer);
        tarball_file = cwd.openFile(tarball_dw_filename, .{});
    } else {
        std.log.info("Found already existing tarball, using that", .{});
    }
}

fn download_tarball(client: *Client, tb_url: []const u8, tb_writer: std.fs.File.Writer) InstallError!void {
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

fn check_hash(hashstr: *const [64]u8, reader: std.fs.File.Reader) !bool {
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
