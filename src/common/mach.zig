const std = @import("std");
const RelError = @import("error.zig").RelError;

pub const MachVersion = union(enum) {
    latest,
    calver: []const u8,
    semantic: []const u8,

    const Self = @This();
    pub const IndexData = struct { version: []const u8, date: []const u8, docs: []const u8, stdDocs: []const u8, machDocs: []const u8, machNominated: []const u8, src: struct { shasum: []const u8, size: u32, tarball: []const u8, zigTarball: []const u8 }, bootstrap: struct { shasum: []const u8, size: u32, tarball: []const u8, zigTarball: []const u8 }, @"x86_64-macos": struct { shasum: []const u8, size: u32, tarball: []const u8, zigTarball: []const u8 }, @"aarch64-macos": struct { shasum: []const u8, size: u32, tarball: []const u8, zigTarball: []const u8 }, @"x86_64-linux": struct { shasum: []const u8, size: u32, tarball: []const u8, zigTarball: []const u8 }, @"aarch64-linux": struct { shasum: []const u8, size: u32, tarball: []const u8, zigTarball: []const u8 }, @"armv7a-linux": struct { shasum: []const u8, size: u32, tarball: []const u8, zigTarball: []const u8 }, @"riscv64-linux": struct { shasum: []const u8, size: u32, tarball: []const u8, zigTarball: []const u8 }, @"powerpc64le-linux": struct { shasum: []const u8, size: u32, tarball: []const u8, zigTarball: []const u8 }, @"x86-linux": struct { shasum: []const u8, size: u32, tarball: []const u8, zigTarball: []const u8 }, @"x86_64-windows": struct { shasum: []const u8, size: u32, tarball: []const u8, zigTarball: []const u8 }, @"aarch64-windows": struct { shasum: []const u8, size: u32, tarball: []const u8, zigTarball: []const u8 }, @"x86-windows": struct { shasum: []const u8, size: u32, tarball: []const u8, zigTarball: []const u8 } };
    const mach_latest_prefix = "mach-latest";
    const mach_suffix = "-mach";

    pub fn parse_str(version: []const u8) RelError!Self {
        if (std.mem.eql(u8, version, mach_latest_prefix)) return Self.latest;

        if (!std.mem.endsWith(u8, version, mach_suffix)) return RelError.InvalidVersionSpec;
        var first_half_iterator = std.mem.tokenizeSequence(u8, version, mach_suffix);
        const prefix = first_half_iterator.next() orelse return RelError.InvalidVersionSpec;

        // For calver version
        if (is_calver(prefix)) return Self{ .calver = version };
        if (is_semantic(prefix)) return Self{ .semantic = version };
        return RelError.InvalidVersionSpec;
    }
};
fn is_calver(version: []const u8) bool {
    var version_iterator = std.mem.tokenizeScalar(u8, version, '.');
    inline for (0..3) |_| {
        const year = version_iterator.next() orelse return false;
        _ = std.fmt.parseInt(u16, year, 10) catch return false;
    }
    return true;
}
fn is_semantic(version: []const u8) bool {
    _ = std.SemanticVersion.parse(version) catch return false;
    return true;
}

test "mach_versioning" {
    //---- Mach Versions
    //mach-latest test
    const mach_latest = try MachVersion.parse_str("mach-latest");
    try std.testing.expectEqual(mach_latest, MachVersion.latest);

    //2024.11.0-mach
    const mach_calver = try MachVersion.parse_str("2024.11.0-mach");
    try std.testing.expectEqual(mach_calver, MachVersion{ .calver = "2024.11.0-mach" });

    //0.4.0-mach
    const mach_semantic = try MachVersion.parse_str("0.4.0-mach");
    try std.testing.expectEqual(mach_semantic, MachVersion{ .calver = "0.4.0-mach" });

    //---- Mach Illformed versions
    const ma = MachVersion.parse_str("0.4.0-ma");
    try std.testing.expectError(RelError.InvalidVersionSpec, ma);

    const semver = MachVersion.parse_str("0.4.0");
    try std.testing.expectError(RelError.InvalidVersionSpec, semver);

    const mach_semver_mach = MachVersion.parse_str("mach.0.4.0-mach");
    try std.testing.expectError(RelError.InvalidVersionSpec, mach_semver_mach);
}
