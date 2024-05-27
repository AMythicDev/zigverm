const std = @import("std");

const targets: []const std.Target.Query = &.{
    .{ .cpu_arch = .x86_64, .os_tag = .macos },
    .{ .cpu_arch = .aarch64, .os_tag = .macos },

    .{ .cpu_arch = .aarch64, .os_tag = .linux },
    .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .x86, .os_tag = .linux, .abi = .gnu },

    .{ .cpu_arch = .x86_64, .os_tag = .windows },
    .{ .cpu_arch = .x86, .os_tag = .windows },
};

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const common = b.createModule(.{ .root_source_file = .{ .path = "src/common/root.zig" } });
    const default_os = target.result.os.tag;
    if (default_os.isBSD() or default_os.isDarwin() or default_os == std.Target.Os.Tag.linux) {
        common.link_libc = true;
    }

    const default_exe = b.addExecutable(.{
        .name = "zigvm",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    default_exe.root_module.addImport("common", common);
    b.installArtifact(default_exe);

    const run_cmd = b.addRunArtifact(default_exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);

    const release_step = b.step("make-release", "Create binaries for releasing");
    for (targets) |t| {
        const name = try std.mem.concat(b.allocator, u8, &.{ "zigvm-", try t.zigTriple(b.allocator) });
        const exe = b.addExecutable(.{
            .name = name,
            .root_source_file = b.path("src/main.zig"),
            .target = b.resolveTargetQuery(t),
            .optimize = .ReleaseSafe,
        });

        const target_output = b.addInstallArtifact(exe, .{});
        release_step.dependOn(&target_output.step);
        exe.root_module.addImport("common", common);
    }
}
