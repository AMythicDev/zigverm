const std = @import("std");
const common = @import("common");
const Allocator = std.mem.Allocator;

pub fn main() !void {
    var aa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = aa.allocator();

    var cp = try common.paths.CommonPaths.resolve(alloc);
    defer cp.close();

    const dir_to_check = try std.process.getCwdAlloc(alloc);

    var overrides = try common.overrides.read_overrides(alloc, cp);
    defer overrides.deinit();

    const best_match = (try overrides.active_version(dir_to_check)).ver;

    const zig_path = try std.fs.path.join(alloc, &.{
        common.paths.CommonPaths.get_zigverm_root(),
        "installs/",
        try common.release_name(alloc, try common.Release.releasefromVersion(best_match)),
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
