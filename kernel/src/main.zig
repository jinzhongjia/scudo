const builtin = @import("builtin");
const lib = @import("lib.zig");
const cpu = @import("cpu.zig");
const kernel_test = @import("kernel_test.zig").test_kernel;

const log = lib.log.scoped(.ZOS);

pub fn main() noreturn {
    lib.tty.init();
    if (!cpu.CPUID.check_available()) {
        @panic("The current computer does not support the cpuid command");
    }
    if (!cpu.MSR.is_avaiable()) {
        @panic("The current computer does not support the MSR");
    }
    lib.idt.init();
    lib.clock.init();
    lib.sound.init();
    lib.time.init();
    lib.mem.init();

    if (builtin.mode != .Debug) {
        lib.tty.clear();
    }

    log.debug("build mode {s}", @tagName(builtin.mode));

    kernel_test();

    @panic(
        \\Note:This is an experimental project!
        \\Now kernel is hang!
    );
}
