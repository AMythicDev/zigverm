const std = @import("std");
const Allocator = std.mem.Allocator;
const StringArrayHashMap = std.StringArrayHashMap;
const json = std.json;
const CommonPaths = @import("paths.zig").CommonPaths;

pub fn read_overrides(alloc: Allocator, cp: CommonPaths) !StringArrayHashMap(json.Value) {
    var file_bufreader = std.io.bufferedReader(cp.overrides.reader());
    var file_reader = file_bufreader.reader();
    var buff: [100]u8 = undefined;

    var overrides: std.StringArrayHashMap(json.Value) = undefined;

    // HACK: Here we are ensuring that the overrides.json file isn't empty, otherwise the json parsing will return an
    // error. Instead if the file is empty, we create ab enott StringArrayHashMap to hold our overrides.
    // Typically we would prefer the pread() function but its currently broken for Windows, hence we do hacky method
    // by checking if there bytes can be read and then resetting the file cursor back to 0.
    if (try file_reader.read(&buff) != 0) {
        try cp.overrides.seekTo(0);
        var json_reader = json.reader(alloc, file_reader);
        overrides = (try json.parseFromTokenSourceLeaky(json.Value, alloc, &json_reader, .{})).object;
    } else {
        overrides = std.StringArrayHashMap(json.Value).init(alloc);
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
