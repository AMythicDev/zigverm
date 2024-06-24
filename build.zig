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

    addExeRunner(b, zigvm, zig);
    addTestRunner(b, target, optimize);
}

fn addExeRunner(b: *std.Build, zigvm: *Compile, zig: *Compile) void {
    const run_zigvm = b.addRunArtifact(zigvm);
    run_zigvm.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_zigvm.addArgs(args);
    }
    const run_zigvm_step = b.step("run-zigvm", "Run the app");
    run_zigvm_step.dependOn(&run_zigvm.step);

    const run_zig = b.addRunArtifact(zig);
    run_zig.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_zig.addArgs(args);
    }
    const run_zig_step = b.step("run-zig", "Run the app");
    run_zig_step.dependOn(&run_zig.step);
}

fn addTestRunner(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
    const zigvm_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_zigvm_tests = b.addRunArtifact(zigvm_tests);

    const zig_tests = b.addTest(.{
        .root_source_file = b.path("src/zig/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_zig_tests = b.addRunArtifact(zig_tests);

    const common_tests = b.addTest(.{
        .root_source_file = b.path("src/common/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const default_os = target.result.os.tag;
    if (default_os.isBSD() or default_os.isDarwin() or default_os == std.Target.Os.Tag.linux) {
        common_tests.linkLibC();
    }
    const run_common_tests = b.addRunArtifact(common_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_zigvm_tests.step);
    test_step.dependOn(&run_zig_tests.step);
    test_step.dependOn(&run_common_tests.step);
}
