const lib = @import("lib.zig");
const kernel_test = @import("kernel_test.zig").test_kernel;

pub fn main() noreturn {
    lib.tty.init();
    lib.idt.init();
    lib.clock.init();
    lib.sound.init();
    lib.time.init();
    lib.mem.init();

    // asm volatile ("xchgw %bx, %bx");
    // asm volatile ("int $0x80");

    kernel_test();

    @panic("Note:This is an experimental project!\nWe're done, just hang...");
}
