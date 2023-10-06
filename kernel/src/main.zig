const lib = @import("lib.zig");

pub fn main() noreturn {
    lib.tty.init();
    lib.idt.init();
    lib.clock.init();
    lib.sound.init();
    // asm volatile ("xchgw %bx, %bx");
    // asm volatile ("int $0x80");

    @panic("Note:This is an experimental project!\nWe're done, just hang...");
}
