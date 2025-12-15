const std = @import("std");
const Compile = std.Build.Step.Compile;

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const strip = if (optimize == std.builtin.OptimizeMode.ReleaseSafe) true else null;
    const default_os = target.result.os.tag;

    const common = b.createModule(.{ .root_source_file = b.path("src/common/root.zig") });
    if (default_os.isBSD() or default_os.isDarwin() or default_os == std.Target.Os.Tag.linux) {
        common.link_libc = true;
    }
    const zip = b.dependency("zip", .{});

    const zigverm = b.addExecutable(
        .{ .name = "zigverm", .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .strip = strip,
        }) },
    );
    zigverm.subsystem = .Console;
    zigverm.root_module.addImport("common", common);
    zigverm.root_module.addImport("zip", zip.module("zip"));

    const zig = b.addExecutable(.{ .name = "zig", .root_module = b.createModule(.{
        .root_source_file = b.path("src/zig/main.zig"),
        .target = target,
        .optimize = optimize,
        .strip = strip,
    }) });
    zig.subsystem = .Console;
    zig.root_module.addImport("common", common);

    const zigverm_setup = b.addExecutable(.{ .name = "zigverm-setup", .root_module = b.createModule(.{
        .root_source_file = b.path("src/zigverm-setup/main.zig"),
        .target = target,
        .optimize = optimize,
        .strip = strip,
    }) });
    zigverm_setup.subsystem = .Console;
    zigverm_setup.root_module.addImport("common", common);
    zigverm_setup.root_module.addImport("zip", zip.module("zip"));

    b.installArtifact(zigverm);
    b.installArtifact(zig);
    b.installArtifact(zigverm_setup);

    addExeRunner(b, zigverm, "run-zigverm");
    addExeRunner(b, zig, "run-zig");
    addExeRunner(b, zigverm_setup, "run-zigverm-setup");
    addTestRunner(b, target, optimize);
}

fn addExeRunner(b: *std.Build, bin: *Compile, name: []const u8) void {
    const run_bin = b.addRunArtifact(bin);
    run_bin.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_bin.addArgs(args);
    }
    const run_zigverm_step = b.step(name, "Run the app");
    run_zigverm_step.dependOn(&run_bin.step);
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
