const std = @import("std");

const Build = std.Build;
const Target = std.Target;
const CrossTarget = std.zig.CrossTarget;
const FileSource = std.build.FileSource;
const Cpu = Target.Cpu;

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    var enabled_features = Cpu.Feature.Set.empty;
    var disabled_features = Cpu.Feature.Set.empty;
    const Feature = Target.x86.Feature;

    disabled_features.addFeature(@enumToInt(Feature.x87));
    disabled_features.addFeature(@enumToInt(Feature.mmx));
    disabled_features.addFeature(@enumToInt(Feature.sse));
    disabled_features.addFeature(@enumToInt(Feature.sse2));
    disabled_features.addFeature(@enumToInt(Feature.avx));
    disabled_features.addFeature(@enumToInt(Feature.avx2));
    disabled_features.addFeature(@enumToInt(Feature.avx512f));

    enabled_features.addFeature(@enumToInt(Feature.soft_float));

    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = CrossTarget{
        // what is the difference between cpu arch x86 and x86_64
        .cpu_arch = .x86,
        // tell compiler the target machine is freestanding
        .os_tag = .freestanding,
        .abi = .gnu,
        .cpu_features_add = enabled_features,
        .cpu_features_sub = disabled_features,
    };

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const kernel = b.addExecutable(.{
        .name = "zos",
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = .{ .path = "src/init/init.zig" },
        .target = target,
        .optimize = optimize,
    });

    kernel.setLinkerScriptPath(.{ .path = "src/link.ld" });

    // kernel.addAssemblyFile("src/boot/start.s");

    const multiboot = b.createModule(.{ .source_file = FileSource.relative("src/multiboot/multiboot.zig") });

    kernel.addModule("multiboot", multiboot);

    const cpu = b.createModule(.{ .source_file = FileSource.relative("src/cpu/cpu.zig") });

    kernel.addModule("cpu", cpu);

    const lib = b.createModule(.{ .source_file = FileSource.relative("src/lib/lib.zig"), .dependencies = &.{ .{
        .name = "cpu",
        .module = cpu,
    }, .{
        .name = "multiboot",
        .module = multiboot,
    } } });

    kernel.addModule("lib", lib);

    // 此处是默认调用的zig build 也就是install
    //
    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(kernel);

    // This *creates* a RunStep in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = b.addRunArtifact(kernel);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
