const std = @import("std");
const common = @import("common");
const Allocator = std.mem.Allocator;

const ExecError = error{VersionNotInstalled};

pub fn main() !void {
    var aa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = aa.allocator();

    var version: ?[]const u8 = null;
    var version_specified = false;
    var args_iter = try std.process.argsWithAllocator(alloc);
    _ = args_iter.next();

    const next_arg = args_iter.next();
    if (next_arg) |arg| {
        if (std.mem.startsWith(u8, arg, "@")) {
            version = arg[1..];
            version_specified = true;
        }
    }

    var cp = try common.paths.CommonPaths.resolve(alloc);
    defer cp.close();

    if (version == null) {
        const dir_to_check = try std.process.getCwdAlloc(alloc);
        var overrides = try common.overrides.read_overrides(alloc, cp);
        defer overrides.deinit();
        version = try alloc.dupe(u8, (try overrides.active_version(dir_to_check)).ver);
    }

    const zig_path = try std.fs.path.join(alloc, &.{
        common.paths.CommonPaths.get_zigverm_root(),
        "installs/",
        try common.release_name(alloc, try common.Release.releaseFromVersion(version.?)),
        "zig",
    });

    var executable: std.ArrayListUnmanaged([]const u8) = .empty;
    try executable.append(alloc, zig_path);

    if (!version_specified) if (next_arg) |arg| try executable.append(alloc, arg);

    while (args_iter.next()) |arg| {
        try executable.append(alloc, arg);
    }

    var child = std.process.Child.init(executable.items, alloc);
    child.stdin = std.fs.File.stdin();
    child.stdout = std.fs.File.stdout();
    child.stderr = std.fs.File.stderr();
    const term = child.spawnAndWait() catch return ExecError.VersionNotInstalled;
    std.process.exit(term.Exited);
}
