const lib = @import("lib.zig");
const println = lib.tty.println;

pub fn main() noreturn {
    lib.tty.init();
    lib.idt.init();
    lib.clock.init();
    lib.sound.init();
    lib.time.init();
    // asm volatile ("xchgw %bx, %bx");
    // asm volatile ("int $0x80");

    var time = lib.time.time_read();
    println("now time is {}-{}-{} {}:{}:{}", .{
        time.year,
        time.month,
        time.day,
        time.hour,
        time.minute,
        time.second,
    });
    @panic("Note:This is an experimental project!\nWe're done, just hang...");
}
