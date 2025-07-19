const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const build_exe = b.option(bool, "exe", "Build the development exe.") orelse false;

    const farbe_module = b.addModule(
        "farbe",
        .{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
        },
    );

    if (build_exe) {
        const exe = b.addExecutable(.{
            .name = "farbe-exe",
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/exe.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "farbe", .module = farbe_module },
                },
            }),
        });
        b.installArtifact(exe);
    }

    const unit_tests = b.addTest(.{
        .root_module = farbe_module,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
