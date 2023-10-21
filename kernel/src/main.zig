const builtin = @import("builtin");
const lib = @import("lib.zig");
const kernel_test = @import("kernel_test.zig").test_kernel;

const log = lib.log.scoped(.ZOS);

pub fn main() noreturn {
    lib.tty.init();
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
