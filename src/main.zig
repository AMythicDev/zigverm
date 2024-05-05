const std = @import("std");
const http = std.http;
const Client = std.http.Client;
const json = std.json;
const builtin = @import("builtin");
const cli = @import("cli.zig");

const Rel = union(enum) { Master, Version: []const u8 };

const InstallError = error{
    ReleaseNotFound,
    InvalidVersion,
};

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

pub fn install_release(_: *Client, releases: json.Parsed(json.Value), rel: Rel) InstallError!void {
    var release: json.Value = undefined;
    switch (rel) {
        Rel.Master => {
            release = releases.value.object.get("master").?;
        },
        Rel.Version => |v| {
            release = releases.value.object.get(v) orelse return InstallError.ReleaseNotFound;
        },
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
