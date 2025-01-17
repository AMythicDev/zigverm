const std = @import("std");
pub const paths = @import("paths.zig");
pub const overrides = @import("overrides.zig");
const Allocator = std.mem.Allocator;
const json = std.json;
const builtin = @import("builtin");
pub const MachVersion = @import("mach.zig").MachVersion;
const RelError = @import("error.zig").RelError;
pub const Cache = @import("cache.zig").Cache;
pub const default_os = builtin.target.os.tag;
pub const default_arch = builtin.target.cpu.arch;

pub const ReleaseSpec = union(enum) { Master, Stable, MajorMinorVersionSpec: []const u8, FullVersionSpec: []const u8, MachVersion: MachVersion };

pub const Release = struct {
    spec: ReleaseSpec,
    actual_version: ?std.SemanticVersion = null,

    const Self = @This();

    pub fn actualVersion(self: Self, alloc: Allocator) RelError![]const u8 {
        switch (self.spec) {
            ReleaseSpec.Master => return try alloc.dupe(u8, "master"),
            ReleaseSpec.FullVersionSpec => |v| return try alloc.dupe(u8, v),
            ReleaseSpec.MachVersion => return try alloc.dupe(u8, self.releaseName()),
            else => {
                if (self.actual_version) |actual_version| {
                    var buffer = std.ArrayList(u8).init(alloc);
                    defer buffer.deinit();
                    try actual_version.format("", .{}, buffer.writer());
                    return try alloc.dupe(u8, buffer.items);
                }
                @panic("actual_version() called without resolving");
            },
        }
    }

    pub fn releaseName(self: Self) []const u8 {
        switch (self.spec) {
            ReleaseSpec.Master => return "master",
            ReleaseSpec.MajorMinorVersionSpec => |v| return v,
            ReleaseSpec.FullVersionSpec => |v| return v,
            ReleaseSpec.Stable => return "stable",
            ReleaseSpec.MachVersion => |v| {
                return switch (v) {
                    MachVersion.latest => "mach-latest",
                    MachVersion.calver => |mach_v| return mach_v,
                    MachVersion.semantic => |mach_v| return mach_v,
                };
            },
        }
    }

    pub fn resolve(self: *Self, releases: json.Value) RelError!void {
        if (self.spec == ReleaseSpec.FullVersionSpec) return;
        if (self.spec == ReleaseSpec.Master) {
            self.actual_version = std.SemanticVersion.parse(releases.object.get("master").?.object.get("version").?.string) catch unreachable;
            return;
        }
        if (self.spec == .MachVersion) {
            return;
        }

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

    pub fn releaseFromVersion(v: []const u8) RelError!Self {
        if (streql(v, "master")) return Self{ .spec = .Master };
        if (streql(v, "stable")) return Self{ .spec = .Stable };
        if (MachVersion.parse_str(v)) |mach| {
            return Self{ .spec = ReleaseSpec{ .MachVersion = mach } };
        } else |_| {}
        const count = std.mem.count(u8, v, ".");
        if (count == 2) {
            return Self{ .spec = ReleaseSpec{ .FullVersionSpec = v }, .actual_version = std.SemanticVersion.parse(v) catch return RelError.InvalidVersionSpec };
        }
        if (completeSpec(v)) |_| {
            return Self{ .spec = ReleaseSpec{ .MajorMinorVersionSpec = v } };
        } else |_| {}
        return RelError.InvalidVersionSpec;
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

pub fn streql(lhs: []const u8, rhs: []const u8) bool {
    return std.mem.eql(u8, lhs, rhs);
}

pub fn release_name(alloc: Allocator, rel: Release) ![]const u8 {
    const release_string = rel.releaseName();
    const dw_target = comptime target_name();
    return try std.mem.concat(alloc, u8, &[_][]const u8{ "zig-" ++ dw_target ++ "-", release_string });
}
