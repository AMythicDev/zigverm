const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const common = b.createModule(.{ .root_source_file = .{ .path = "src/common/root.zig" } });
    const default_os = target.result.os.tag;
    if (default_os.isBSD() or default_os.isDarwin() or default_os == std.Target.Os.Tag.linux) {
        common.link_libc = true;
    }

    const strip = if (optimize == std.builtin.OptimizeMode.ReleaseSafe) true else null;

    const zigvm = b.addExecutable(.{
        .name = "zigvm",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .strip = strip,
    });
    const zig = b.addExecutable(.{
        .name = "zig",
        .root_source_file = b.path("src/zig//main.zig"),
        .target = target,
        .optimize = optimize,
        .strip = strip,
    });

    zigvm.root_module.addImport("common", common);
    zig.root_module.addImport("common", common);
    b.installArtifact(zigvm);
    b.installArtifact(zig);

    const run_cmd = b.addRunArtifact(zigvm);
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
}
