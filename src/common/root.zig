const std = @import("std");
pub const paths = @import("paths.zig");
pub const overrides = @import("overrides.zig");
const Allocator = std.mem.Allocator;
const json = std.json;
const builtin = @import("builtin");

pub const default_os = builtin.target.os.tag;
pub const default_arch = builtin.target.cpu.arch;

const RelError = error{
    InvalidVersion,
};

pub const Rel = union(enum) {
    Master,
    Stable: ?[]const u8,
    Version: []const u8,

    const Self = @This();

    pub fn version(self: Self) []const u8 {
        switch (self) {
            Rel.Master => return "master",
            Rel.Stable => |ver| {
                if (ver) |v| {
                    return v;
                } else {
                    @panic("Rel.version() called when Rel.Stable is not resolved");
                }
            },
            Rel.Version => |v| return v,
        }
    }

    pub fn as_string(self: Self) []const u8 {
        switch (self) {
            Rel.Master => return "master",
            Rel.Version => |v| return v,
            Rel.Stable => return "stable",
        }
    }

    fn resolve_stable_release(alloc: Allocator, releases: json.Value) std.ArrayList(u8) {
        var buf = std.ArrayList(u8).init(alloc);
        var stable: ?std.SemanticVersion = null;
        for (releases.object.keys()) |release| {
            if (streql(release, "master")) continue;
            var r = std.SemanticVersion.parse(release) catch unreachable;
            if (stable == null) {
                stable = r;
                continue;
            }
            if (r.order(stable.?) == std.math.Order.gt) {
                stable = r;
            }
        }
        stable.?.format("", .{}, buf.writer()) catch unreachable;
        return buf;
    }

    pub fn releasefromVersion(alloc: Allocator, releases: ?json.Value, v: []const u8) RelError!Self {
        var rel: Rel = undefined;
        if (streql(v, "master")) {
            rel = Rel.Master;
        } else if (streql(v, "stable")) {
            if (releases) |r| {
                rel = Rel{ .Stable = Rel.resolve_stable_release(alloc, r).items };
            } else {
                rel = Rel{ .Stable = null };
            }
        } else if (std.SemanticVersion.parse(v)) |_| {
            rel = Rel{ .Version = v };
        } else |_| {
            return RelError.InvalidVersion;
        }
        return rel;
    }
};

pub fn target_name() []const u8 {
    return @tagName(default_arch) ++ "-" ++ @tagName(default_os);
}

pub fn streql(cmd: []const u8, key: []const u8) bool {
    return std.mem.eql(u8, cmd, key);
}

pub fn release_name(alloc: Allocator, rel: Rel) ![]const u8 {
    const release_string = rel.as_string();
    const dw_target = comptime target_name();
    return try std.mem.concat(alloc, u8, &[_][]const u8{ "zig-" ++ dw_target ++ "-", release_string });
}
