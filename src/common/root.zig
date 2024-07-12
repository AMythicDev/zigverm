const std = @import("std");
pub const paths = @import("paths.zig");
pub const overrides = @import("overrides.zig");
const Allocator = std.mem.Allocator;
const json = std.json;
const builtin = @import("builtin");

pub const default_os = builtin.target.os.tag;
pub const default_arch = builtin.target.cpu.arch;

const RelError = error{
    InvalidVersionSpec,
    Overflow,
    OutOfMemory,
};

pub const ReleaseSpec = union(enum) { Master, Stable, MajorMinorVersionSpec: []const u8, FullVersionSpec: []const u8 };

pub const Release = struct {
    spec: ReleaseSpec,
    actual_version: ?std.SemanticVersion = null,

    const Self = @This();

    pub fn actualVersion(self: Self, alloc: Allocator) RelError![]const u8 {
        switch (self.spec) {
            ReleaseSpec.Master => return try alloc.dupe(u8, "master"),
            ReleaseSpec.FullVersionSpec => |v| return try alloc.dupe(u8, v),
            else => {
                if (self.actual_version == null) @panic("actual_version() called without resolving");
                var buffer = std.ArrayList(u8).init(alloc);
                defer buffer.deinit();
                try self.actual_version.?.format("", .{}, buffer.writer());
                return try alloc.dupe(u8, buffer.items);
            },
        }
    }

    pub fn releaseName(self: Self) []const u8 {
        switch (self.spec) {
            ReleaseSpec.Master => return "master",
            ReleaseSpec.MajorMinorVersionSpec => |v| return v,
            ReleaseSpec.FullVersionSpec => |v| return v,
            ReleaseSpec.Stable => return "stable",
        }
    }

    pub fn resolve(self: *Self, releases: json.Value) RelError!void {
        if (self.spec == ReleaseSpec.Master or self.spec == ReleaseSpec.FullVersionSpec) return;

        var base_spec: std.SemanticVersion = undefined;
        if (self.spec == .Stable) {
            base_spec = std.SemanticVersion{ .major = 0, .minor = 0, .patch = 0 };
        } else {
            base_spec = try Self.completeSpec(self.spec.MajorMinorVersionSpec);
        }

        for (releases.object.keys()) |release| {
            if (streql(release, "master")) continue;

            var r = std.SemanticVersion.parse(release) catch unreachable;

            if (self.spec == .MajorMinorVersionSpec and (base_spec.major != r.major or base_spec.minor != r.minor)) continue;

            if (self.actual_version == null) {
                self.actual_version = r;
                continue;
            }

            if (r.order(self.actual_version.?) == std.math.Order.gt) {
                self.actual_version = r;
            }
        }
    }

    pub fn releasefromVersion(v: []const u8) RelError!Self {
        var rel: Release = undefined;
        if (streql(v, "master"))
            rel = Self{ .spec = .Master }
        else if (streql(v, "stable"))
            rel = Self{ .spec = .Stable }
        else b: {
            const count = std.mem.count(u8, v, ".");
            if (count == 2) {
                rel = Self{ .spec = ReleaseSpec{ .FullVersionSpec = v }, .actual_version = std.SemanticVersion.parse(v) catch return RelError.InvalidVersionSpec };
                break :b;
            }

            const is_valid_version = completeSpec(v);
            if (is_valid_version) |_| {
                rel = Self{ .spec = ReleaseSpec{ .MajorMinorVersionSpec = v } };
            } else |_| _ = try is_valid_version;
        }
        return rel;
    }

    pub inline fn completeSpec(spec: []const u8) RelError!std.SemanticVersion {
        const count = std.mem.count(u8, spec, ".");
        var buffer = try std.BoundedArray(u8, 24).fromSlice(spec);

        if (count == 2)
            return std.SemanticVersion.parse(spec) catch return RelError.InvalidVersionSpec
        else if (count == 1) {
            try buffer.appendSlice(".0");
            return std.SemanticVersion.parse(buffer.slice()) catch return RelError.InvalidVersionSpec;
        } else return RelError.InvalidVersionSpec;
    }
};

pub fn target_name() []const u8 {
    return @tagName(default_arch) ++ "-" ++ @tagName(default_os);
}

pub fn streql(cmd: []const u8, key: []const u8) bool {
    return std.mem.eql(u8, cmd, key);
}

pub fn release_name(alloc: Allocator, rel: Release) ![]const u8 {
    const release_string = rel.releaseName();
    const dw_target = comptime target_name();
    return try std.mem.concat(alloc, u8, &[_][]const u8{ "zig-" ++ dw_target ++ "-", release_string });
}

test {
    std.testing.refAllDecls(@This());
}
