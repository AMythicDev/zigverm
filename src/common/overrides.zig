const std = @import("std");
const Allocator = std.mem.Allocator;
const StringArrayHashMap = std.StringArrayHashMap;
const json = std.json;
const CommonPaths = @import("paths.zig").CommonPaths;
const File = std.fs.File;
const Io = std.Io;

pub const OverrideMap = struct {
    backing_map: json.ObjectMap,
    allocator: Allocator,

    const Self = @This();

    pub fn deinit(self: *Self) void {
        var iter = self.backing_map.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*.string);
        }
        self.backing_map.deinit();
    }

    pub fn addOverride(self: *Self, dir: []const u8, release_name: []const u8) !void {
        try self.backing_map.put(dir, json.Value{ .string = try self.allocator.dupe(u8, release_name) });
    }

    pub fn active_version(self: Self, dir_to_check: []const u8) !struct { from: []const u8, ver: []const u8 } {
        var from = dir_to_check;
        var best_match: ?[]const u8 = null;

        while (true) {
            if (self.backing_map.get(from)) |val| {
                best_match = val.string;
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
            best_match = self.backing_map.get("default").?.string;
            from = "default";
        }

        return .{ .from = from, .ver = best_match.? };
    }
};

pub fn read_overrides(alloc: Allocator, io: Io, cp: CommonPaths) !OverrideMap {
    var buf: [4096]u8 = undefined;
    var file_bufreader = cp.overrides.reader(io, &buf);
    const file_reader = &file_bufreader.interface;

    var overrides = OverrideMap{ .backing_map = json.ObjectMap.init(alloc), .allocator = alloc };

    // HACK: Here we are ensuring that the overrides.json file isn't empty, otherwise the json parsing will return an
    // error. Instead if the file is empty, we create StringArrayHashMap to hold our overrides.
    // Typically we would prefer the pread() function but its currently broken for Windows, hence we do hacky method
    // by checking if there bytes can be read and then resetting the file cursor back to 0.
    if (try cp.overrides.getEndPos() != 0) {
        try cp.overrides.seekTo(0);
        var json_reader = json.Reader.init(alloc, file_reader);
        const parsed = try json.parseFromTokenSource(json.Value, alloc, &json_reader, .{});
        defer {
            json_reader.deinit();
            parsed.deinit();
        }

        var iter = parsed.value.object.iterator();
        while (iter.next()) |entry| {
            const string = try alloc.dupe(u8, entry.value_ptr.*.string);
            _ = try overrides.backing_map.fetchPut(try alloc.dupe(u8, entry.key_ptr.*), json.Value{ .string = string });
        }
    }

    return overrides;
}

pub fn write_overrides(overrides: OverrideMap, cp: CommonPaths) !void {
    // NOTE: VERY IMPORTANT LINE FOR NOT SPAGHETTIFYING THE WHOLE FILE:
    // What we are effectively trying to do is truncate the file to zero length. For that we use the `setEndPos`
    // function. `setEndPos` resizes the file based on the current file cursor postion. It is sure that the file cursor
    // will be at the end of the file after all the above reading, hence we reset the cursor back to 0 so that there
    // isn't any weird byte writings at the beginning of the file.
    try cp.overrides.seekTo(0);
    try cp.overrides.setEndPos(0);
    var buf: [4096]u8 = undefined;
    var file_writer = cp.overrides.writer(&buf);
    const intf = &file_writer.interface;

    try json.Stringify.value(json.Value{ .object = overrides.backing_map }, .{ .whitespace = .indent_2 }, intf);
    _ = try intf.write("\n");
    try file_writer.end();
}
