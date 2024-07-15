const std = @import("std");
const builtin = @import("builtin");

// min zig version for build
const min_zig_version = std.SemanticVersion{ .major = 0, .minor = 12, .patch = 0 };

// detect the zig version
comptime {
    const current_zig_version = builtin.zig_version;
    if (current_zig_version.order(min_zig_version) == .lt) {
        @compileError(std.fmt.comptimePrint("Your Zig version v{} does not meet the minimum build requirement of v{}", .{ current_zig_version, min_zig_version }));
    }
}

// Define a freestanding x86_64 cross-compilation target.
const target_query = blk: {
    const Features = std.Target.x86.Feature;
    var result = std.Target.Query{
        .cpu_arch = .x86_64,
        .os_tag = .freestanding,
        .abi = .none,
    };

    // Disable CPU features that require additional initialization
    // like MMX, SSE/2 and AVX. That requires us to enable the soft-float feature.
    result.cpu_features_sub.addFeature(@intFromEnum(Features.mmx));
    result.cpu_features_sub.addFeature(@intFromEnum(Features.sse));
    result.cpu_features_sub.addFeature(@intFromEnum(Features.sse2));
    result.cpu_features_sub.addFeature(@intFromEnum(Features.avx));
    result.cpu_features_sub.addFeature(@intFromEnum(Features.avx2));
    result.cpu_features_add.addFeature(@intFromEnum(Features.soft_float));

    break :blk result;
};

pub fn build(b: *std.Build) !void {
    const options = b.addOptions();
    options.addOption(u64, "timeStamp", @as(u64, @intCast(std.time.timestamp())));

    // Build the kernel itself.
    const optimize = b.standardOptimizeOption(.{});
    const kernel = b.addExecutable(.{
        .name = "kernel",
        .root_source_file = b.path("src/start.zig"),
        .target = b.resolveTargetQuery(target_query),
        .optimize = optimize,
        .code_model = .kernel,
        .pic = true,
    });

    const config = b.createModule(.{
        .root_source_file = b.path("config.zig"),
    });

    kernel.root_module.addOptions("build_info", options);
    kernel.root_module.addImport("config", config);

    const limine = b.dependency("limine", .{});
    kernel.root_module.addImport("limine", limine.module("limine"));

    kernel.setLinkerScriptPath(b.path("linker.ld"));

    b.installArtifact(kernel);
}
