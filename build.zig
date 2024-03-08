const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const build_exe = b.option(bool, "exe", "Build the development exe.") orelse false;
    const build_picker = b.option(bool, "picker", "Build the colour picker utility executible.") orelse false;

    const farbe_module = b.addModule(
        "farbe",
        .{ .root_source_file = .{ .path = "src/main.zig" } },
    );

    if (build_exe) {
        const exe = b.addExecutable(.{
            .name = "farbe-exe",
            .root_source_file = .{ .path = "src/exe.zig" },
            .target = target,
            .optimize = optimize,
        });
        exe.root_module.addImport("farbe", farbe_module);
        b.installArtifact(exe);
    }

    if (build_picker) {
        const picker = b.addExecutable(.{
            .name = "picker",
            .root_source_file = .{ .path = "src/picker.zig" },
            .target = target,
            .optimize = optimize,
        });
        picker.root_module.addImport("farbe", farbe_module);
        b.installArtifact(picker);
    }

    const unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
