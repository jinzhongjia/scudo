const std = @import("std");
const builtin = @import("builtin");

// min zig version for build
const min_zig_version = std.SemanticVersion{ .major = 0, .minor = 11, .patch = 0 };

pub fn build(b: *std.Build) !void {
    comptime {
        const current_zig_version = builtin.zig_version;
        if (current_zig_version.order(min_zig_version) == .lt) {
            @compileError(std.fmt.comptimePrint("Your Zig version v{} does not meet the minimum build requirement of v{}", .{ current_zig_version, min_zig_version }));
        }
    }

    // Define a freestanding x86_64 cross-compilation target.
    var target: std.zig.CrossTarget = .{
        .cpu_arch = .x86_64,
        .os_tag = .freestanding,
        .abi = .none,
    };

    // Disable CPU features that require additional initialization
    // like MMX, SSE/2 and AVX. That requires us to enable the soft-float feature.
    const Features = std.Target.x86.Feature;
    target.cpu_features_sub.addFeature(@intFromEnum(Features.mmx));
    target.cpu_features_sub.addFeature(@intFromEnum(Features.sse));
    target.cpu_features_sub.addFeature(@intFromEnum(Features.sse2));
    target.cpu_features_sub.addFeature(@intFromEnum(Features.avx));
    target.cpu_features_sub.addFeature(@intFromEnum(Features.avx2));
    target.cpu_features_add.addFeature(@intFromEnum(Features.soft_float));

    const options = b.addOptions();
    options.addOption(u64, "timeStamp", @as(u64, @intCast(std.time.timestamp())));

    // Build the kernel itself.
    const optimize = b.standardOptimizeOption(.{});
    const limine = b.dependency("limine", .{});
    const kernel = b.addExecutable(.{
        .name = "kernel",
        .root_source_file = .{ .path = "src/start.zig" },
        .target = target,
        .optimize = optimize,
    });

    // trip the symbols when build ReleaseSafe
    if (kernel.optimize == .ReleaseSafe or kernel.optimize == .ReleaseFast) {
        kernel.strip = true;
    }
    kernel.code_model = .kernel;

    kernel.addOptions("build_info", options);
    kernel.code_model = .kernel;

    kernel.addModule("limine", limine.module("limine"));
    kernel.addAnonymousModule("config", .{
        .source_file = std.Build.LazyPath.relative("config.zig"),
    });
    kernel.setLinkerScriptPath(.{ .path = "linker.ld" });
    kernel.pie = true;

    b.installArtifact(kernel);
}
