const std = @import("std");
const json = std.json;
const Allocator = std.mem.Allocator;
const Release = @import("./root.zig").Release;

fn make_mock_releases(alloc: Allocator) !std.StringArrayHashMap(json.Value) {
    var releases_map = json.ObjectMap.init(alloc);
    _ = try releases_map.fetchPut("0.1.0", .null);
    _ = try releases_map.fetchPut("0.2.0", .null);
    _ = try releases_map.fetchPut("0.3.0", .null);
    _ = try releases_map.fetchPut("0.4.0", .null);
    _ = try releases_map.fetchPut("0.5.0", .null);
    _ = try releases_map.fetchPut("0.6.0", .null);
    _ = try releases_map.fetchPut("0.7.0", .null);
    _ = try releases_map.fetchPut("0.8.0", .null);
    _ = try releases_map.fetchPut("0.9.0", .null);
    _ = try releases_map.fetchPut("0.10.0", .null);
    _ = try releases_map.fetchPut("0.10.1", .null);
    _ = try releases_map.fetchPut("0.11.0", .null);
    _ = try releases_map.fetchPut("0.12.0", .null);
    _ = try releases_map.fetchPut("master", .null);

    return releases_map;
}

test "Resolve exact version" {
    const alloc = std.testing.allocator;

    var releases_map = try make_mock_releases(alloc);
    defer releases_map.deinit();
    const releases = json.Value{ .object = releases_map };

    var rel = try Release.releaseFromVersion("0.12.0");
    try rel.resolve(releases);

    const v = try rel.actualVersion(alloc);
    defer alloc.free(v);
    try std.testing.expectEqualStrings("0.12.0", v);
}

test "Resolve patch version with no patch releases" {
    const alloc = std.testing.allocator;

    var releases_map = try make_mock_releases(alloc);
    defer releases_map.deinit();
    const releases = json.Value{ .object = releases_map };

    var rel = try Release.releasefromVersion("0.12");
    try rel.resolve(releases);

    const v = try rel.actualVersion(alloc);
    defer alloc.free(v);
    try std.testing.expectEqualStrings("0.12.0", v);
}

test "Resolve patch version with patch releases" {
    const alloc = std.testing.allocator;

    var releases_map = try make_mock_releases(alloc);
    defer releases_map.deinit();
    const releases = json.Value{ .object = releases_map };

    var rel = try Release.releasefromVersion("0.10");
    try rel.resolve(releases);

    const v = try rel.actualVersion(alloc);
    defer alloc.free(v);
    try std.testing.expectEqualStrings("0.10.1", v);
}

test "Resolve stable" {
    const alloc = std.testing.allocator;

    var releases_map = try make_mock_releases(alloc);
    defer releases_map.deinit();
    const releases = json.Value{ .object = releases_map };

    var rel = try Release.releasefromVersion("stable");
    try rel.resolve(releases);

    const v = try rel.actualVersion(alloc);
    defer alloc.free(v);
    try std.testing.expectEqualStrings("0.12.0", v);
}
