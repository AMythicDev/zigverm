const std = @import("std");
const Compile = std.Build.Step.Compile;

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const common = b.createModule(.{ .root_source_file = b.path("src/common/root.zig") });
    const default_os = target.result.os.tag;
    if (default_os.isBSD() or default_os.isDarwin() or default_os == std.Target.Os.Tag.linux) {
        common.link_libc = true;
    }

    const strip = if (optimize == std.builtin.OptimizeMode.ReleaseSafe) true else null;

    const zigverm = b.addExecutable(
        .{ .name = "zigverm", .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .strip = strip,
        }) },
    );
    const zig = b.addExecutable(.{ .name = "zig", .root_module = b.createModule(.{
        .root_source_file = b.path("src/zig/main.zig"),
        .target = target,
        .optimize = optimize,
        .strip = strip,
    }) });

    zigverm.root_module.addImport("common", common);
    // zigverm.root_module.addImport("zip", zip.module("zip"));
    zig.root_module.addImport("common", common);
    b.installArtifact(zigverm);
    b.installArtifact(zig);

    addExeRunner(b, zigverm, zig);
    addTestRunner(b, target, optimize);
}

fn addExeRunner(b: *std.Build, zigverm: *Compile, zig: *Compile) void {
    const run_zigverm = b.addRunArtifact(zigverm);
    run_zigverm.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_zigverm.addArgs(args);
    }
    const run_zigverm_step = b.step("run-zigverm", "Run the app");
    run_zigverm_step.dependOn(&run_zigverm.step);

    const run_zig = b.addRunArtifact(zig);
    run_zig.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_zig.addArgs(args);
    }
    const run_zig_step = b.step("run-zig", "Run the app");
    run_zig_step.dependOn(&run_zig.step);
}

fn addTestRunner(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
    const zigverm_tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    }) });
    const run_zigverm_tests = b.addRunArtifact(zigverm_tests);

    const zig_tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/zig/main.zig"),
        .target = target,
        .optimize = optimize,
    }) });
    const run_zig_tests = b.addRunArtifact(zig_tests);

    const common_tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/zig/main.zig"),
        .target = target,
        .optimize = optimize,
    }) });
    const default_os = target.result.os.tag;
    if (default_os.isBSD() or default_os.isDarwin() or default_os == std.Target.Os.Tag.linux) {
        common_tests.linkLibC();
    }
    const run_common_tests = b.addRunArtifact(common_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_zigverm_tests.step);
    test_step.dependOn(&run_zig_tests.step);
    test_step.dependOn(&run_common_tests.step);
}
