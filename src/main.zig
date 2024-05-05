const std = @import("std");
const http = std.http;
const Client = std.http.Client;
const json = std.json;
const builtin = @import("builtin");
const cli = @import("cli.zig");
const File = std.fs.file;

const Rel = union(enum) { Master, Version: []const u8 };

const InstallError = error{
    ReleaseNotFound,
    InvalidVersion,
    TargetNotAvailable,
} || std.Uri.ParseError || Client.RequestError || Client.Request.WaitError || std.fs.File.OpenError || Client.Request.ReadError || std.posix.WriteError;

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
                return try install_release(&client, releases, Rel.Master);
            } else if (std.SemanticVersion.parse(rel)) |_| {
                try install_release(&client, releases, Rel{ .Version = rel });
            } else |_| {
                return InstallError.InvalidVersion;
            }
        },
    }
}

pub fn install_release(client: *Client, releases: json.Parsed(json.Value), rel: Rel) InstallError!void {
    var release: json.Value = undefined;
    var release_string = undefined;
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
    const tarball_dw_filename = "zig-" ++ dw_target ++ "-" ++ release_string ++ ".tar.xz.partial";

    const cwd = std.fs.cwd();
    const tarball = try cwd.createFile(tarball_dw_filename, .{});
    defer tarball.close();
    download_tarball(client, tarball_url, tarball);
}

fn download_tarball(client: *Client, tb_url: []const u8, tarball: *File) InstallError!void {
    const tarball_uri = try std.Uri.parse(tb_url);

    var http_header_buff: [1024]u8 = undefined;
    var req = try client.open(http.Method.GET, tarball_uri, Client.RequestOptions{ .server_header_buffer = &http_header_buff });
    defer req.deinit();

    try req.send();
    try req.wait();
    var reader = req.reader();

    var tarball_writer = tarball.writer();
    var buff: [1024]u8 = undefined;
    while (true) {
        const len = try reader.read(&buff);
        if (len == 0) {
            break;
        }
        _ = try tarball_writer.write(buff[0..len]);
    }
}

fn get_json_dslist(client: *Client) anyerror!JsonResponse {
    const uri = try std.Uri.parse("https://ziglang.org/download/index.json");

    var http_header_buff: [1024]u8 = undefined;
    var req = try client.open(
        http.Method.GET,
        uri,
        Client.RequestOptions{ .server_header_buffer = &http_header_buff },
    );
    defer req.deinit();

    try req.send();
    try req.wait();

    var json_buff: [1024 * 100]u8 = undefined;
    const bytes_read = try req.reader().readAll(&json_buff);

    return JsonResponse{ .body = json_buff, .length = bytes_read };
}
