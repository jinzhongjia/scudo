const lib = @import("lib.zig");
const cpu = @import("cpu.zig");
const kernel_test = @import("kernel_test.zig").test_kernel;

pub fn main() noreturn {
    lib.tty.init();
    // Check whether the CPU supports required features
    detect();
    // Initialize basic modules
    module_init();

    // test unit for kernel
    kernel_test();

    @panic(
        \\Note:This is an experimental project!
        \\Now kernel is hang!
    );
}

inline fn module_init() void {
    lib.idt.init();
    lib.clock.init();
    lib.sound.init();
    lib.time.init();
    lib.mem.init();
}

inline fn detect() void {
    if (!cpu.CPUID.check_available()) {
        @panic("The current computer does not support the cpuid command");
    }
    if (!cpu.MSR.is_avaiable()) {
        @panic("The current computer does not support the MSR");
    }
}
