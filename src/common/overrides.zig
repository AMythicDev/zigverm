const std = @import("std");
const Allocator = std.mem.Allocator;
const StringArrayHashMap = std.StringArrayHashMap;
const json = std.json;
const CommonPaths = @import("paths.zig").CommonPaths;

pub const OverrideMap = struct {
    backing_map: StringArrayHashMap([]const u8),

    const Self = @This();

    fn deinit(self: *Self) void {
        var iter = self.backing_map.iterator();
        while (iter.next()) |entry| {
            std.testing.allocator.free(entry.key_ptr.*);
            std.testing.allocator.free(entry.value_ptr.*);
        }
        self.backing_map.deinit();
    }

    pub fn active_version(self: Self, dir_to_check: []const u8) !struct { from: []const u8, ver: []const u8 } {
        var from = dir_to_check;
        var best_match: ?[]const u8 = null;

        while (true) {
            if (self.backing_map.get(from)) |val| {
                best_match = val;
                break;
            } else {
                const next_dir_to_check = std.fs.path.dirname(from);

                if (next_dir_to_check) |d|
                    from = @constCast(d)
                else
                    break;
            }
        }

        if (best_match == null) {
            best_match = try self.backing_map.get("default").?;
            from = "default";
        }

        return .{ .from = from, .ver = best_match.? };
    }
};

pub fn read_overrides(alloc: Allocator, cp: CommonPaths) !OverrideMap {
    var file_bufreader = std.io.bufferedReader(cp.overrides.reader());
    var file_reader = file_bufreader.reader();
    var buff: [100]u8 = undefined;

    var overrides = OverrideMap{ .backing_map = StringArrayHashMap([]const u8).init(alloc) };

    // HACK: Here we are ensuring that the overrides.json file isn't empty, otherwise the json parsing will return an
    // error. Instead if the file is empty, we create ab enott StringArrayHashMap to hold our overrides.
    // Typically we would prefer the pread() function but its currently broken for Windows, hence we do hacky method
    // by checking if there bytes can be read and then resetting the file cursor back to 0.
    if (try file_reader.read(&buff) != 0) {
        try cp.overrides.seekTo(0);
        var json_reader = json.reader(alloc, file_reader);
        const parsed = try json.parseFromTokenSource(json.Value, alloc, &json_reader, .{});
        defer {
            json_reader.deinit();
            parsed.deinit();
        }

        var iter = parsed.value.object.iterator();
        while (iter.next()) |entry| {
            _ = try overrides.backing_map.fetchPut(try alloc.dupe(u8, entry.key_ptr.*), try alloc.dupe(u8, entry.value_ptr.*.string));
        }
    }

    return overrides;
}

pub fn write_overrides(overrides: StringArrayHashMap(json.Value), cp: CommonPaths) !void {
    // NOTE: VERY IMPORTANT LINE FOR NOT SPAGHETTIFYING THE WHOLE FILE:
    // What we are effectively trying to do is truncate the file to zero length. For that we use the `setEndPos`
    // function. `setEndPos` resizes the file based on the current file cursor postion. It is sure that the file cursor
    // will be at the end of the file after all the above reading, hence we reset the cursor back to 0 so that there
    // isn't any weird byte writings at the beginning of the file.
    try cp.overrides.seekTo(0);
    try cp.overrides.setEndPos(0);
    var file_writer = std.io.bufferedWriter(cp.overrides.writer());
    try json.stringify(json.Value{ .object = overrides }, .{ .whitespace = .indent_4 }, file_writer.writer());
    _ = try file_writer.write("\n");
    try file_writer.flush();
}
