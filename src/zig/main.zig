const std = @import("std");
const common = @import("common");
const Allocator = std.mem.Allocator;

pub fn main() !void {
    var aa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = aa.allocator();

    var cp = try common.paths.CommonPaths.resolve(alloc);
    defer cp.clone();

    const overrides = try common.overrides.read_overrides(alloc, cp);

    var dir_to_check = try std.process.getCwdAlloc(alloc);

    var best_match: ?[]const u8 = null;

    while (true) {
        if (overrides.get(dir_to_check)) |val| {
            best_match = val.string;
            break;
        } else {
            const next_dir_to_check = std.fs.path.dirname(dir_to_check);

            if (next_dir_to_check) |d|
                dir_to_check = @constCast(d)
            else
                break;
        }
    }

    if (best_match == null)
        best_match = overrides.get("default").?.string;

    const zig_path = try std.fs.path.join(alloc, &.{
        common.paths.CommonPaths.get_zigvm_root(),
        "installs/",
        try common.release_name(alloc, try common.Rel.releasefromVersion(alloc, null, best_match.?)),
        "zig",
    });

    var executable = std.ArrayList([]const u8).init(alloc);
    try executable.append(zig_path);

    var args_iter = try std.process.argsWithAllocator(alloc);
    _ = args_iter.next();

    while (args_iter.next()) |arg| {
        try executable.append(arg);
    }

    var child = std.process.Child.init(executable.items, alloc);
    child.stdin = std.io.getStdIn();
    child.stdout = std.io.getStdOut();
    child.stderr = std.io.getStdErr();
    const term = try child.spawnAndWait();
    std.process.exit(term.Exited);
}
