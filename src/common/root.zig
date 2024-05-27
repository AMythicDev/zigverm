const std = @import("std");
pub const paths = @import("paths.zig");
pub const overrides = @import("overrides.zig");

pub fn streql(cmd: []const u8, key: []const u8) bool {
    return std.mem.eql(u8, cmd, key);
}
