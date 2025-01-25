const std = @import("std");
const builtin = @import("builtin");
// Cache requires a function (lambda) to be called when there's no cache hit and an other function(args_to_u64) that can compute args
// of the function to u64 that becomes the identifier to compare same arguments.

pub fn Cache(lambda: anytype, args_to_u64: fn (anytype) u64) type {
    const lambda_info = @typeInfo(@TypeOf(lambda));
    if (lambda_info != .Fn) {
        @compileError("lambda should be a function type");
    }
    const return_type = lambda_info.Fn.return_type orelse @compileError("No return type");
    const return_type_info = @typeInfo(return_type);
    const return_error_union_type = if (return_type_info == .ErrorUnion) blk: {
        break :blk .{ return_type_info.ErrorUnion.error_set || std.mem.Allocator.Error, return_type_info.ErrorUnion.payload };
    } else blk: {
        break :blk .{ std.mem.Allocator.Error, return_type };
    };
    // @compileLog(@typeName(return_type));
    const InnerHashMap = std.HashMap(u64, return_type, struct {
        pub fn hash(_: @This(), key: u64) u64 {
            return key;
        }
        pub fn eql(_: @This(), a: u64, b: u64) bool {
            return a == b;
        }
    }, 80);
    return struct {
        _inner: InnerHashMap,
        const Self = @This();
        pub fn init(allocator: std.mem.Allocator) Self {
            return Self{ ._inner = InnerHashMap.init(allocator) };
        }
        pub fn deinit(self: *Self) void {
            self._inner.deinit();
        }

        pub fn get(self: *Self, args: anytype) return_error_union_type[0]!struct { bool, return_error_union_type[1] } {
            const key = args_to_u64(args);
            if (self._inner.get(key)) |value| {
                var payload: return_error_union_type[1] = undefined;
                if (comptime return_type_info == .ErrorUnion) {
                    payload = try value;
                } else {
                    payload = value;
                }
                return .{ true, payload };
            } else {
                const value = @call(.auto, lambda, args);
                try self._inner.put(key, value);
                var payload: return_error_union_type[1] = undefined;
                if (comptime return_type_info == .ErrorUnion) {
                    payload = try value;
                } else {
                    payload = value;
                }
                return .{ false, payload };
            }
        }
    };
}

//// Test
// Below tests to cache addition of two numbers
fn _add(a: u64, b: u64) u64 {
    return a + b;
}

const HashAdd = struct {
    var allocator: std.mem.Allocator = undefined;
    pub fn hash_add(args: anytype) u64 {
        const temp = std.fmt.allocPrint(allocator, "{}:{}", .{ args[0], args[1] }) catch unreachable;
        defer allocator.free(temp);
        return std.hash_map.hashString(temp);
    }
};

test "test_cache" {
    const allocator = std.testing.allocator;
    HashAdd.allocator = allocator;
    var cache = Cache(_add, HashAdd.hash_add).init(allocator);
    var is_Cache_hit: bool, var value: u64 = try cache.get(.{ 1, 2 });
    try std.testing.expectEqual(false, is_Cache_hit);
    try std.testing.expectEqual(3, value);
    is_Cache_hit, value = try cache.get(.{ 1, 2 });
    try std.testing.expectEqual(true, is_Cache_hit);
    try std.testing.expectEqual(3, value);
    cache._inner.deinit();
}

fn _add_error(a: u64, b: u64) error{Got5}!u64 {
    if (a + b == 5) {
        return error.Got5;
    }
    return a + b;
}

test "test_add_error" {
    const allocator = std.testing.allocator;
    HashAdd.allocator = allocator;
    var cache = Cache(_add_error, HashAdd.hash_add).init(allocator);
    var is_Cache_hit: bool, var value: u64 = try cache.get(.{ 1, 2 });
    try std.testing.expectEqual(false, is_Cache_hit);
    try std.testing.expectEqual(3, value);
    is_Cache_hit, value = try cache.get(.{ 1, 2 });
    try std.testing.expectEqual(true, is_Cache_hit);
    try std.testing.expectEqual(3, value);

    try std.testing.expectError(error.Got5, cache.get(.{ 1, 4 }));
    cache._inner.deinit();
}
