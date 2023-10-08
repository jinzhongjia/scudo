const lib = @import("lib.zig");
const println = lib.tty.println;

pub fn main() noreturn {
    lib.tty.init();
    lib.idt.init();
    lib.clock.init();
    lib.sound.init();
    lib.time.init();
    lib.mem.init();

    // asm volatile ("xchgw %bx, %bx");
    // asm volatile ("int $0x80");

    test_kernel();

    @panic("Note:This is an experimental project!\nWe're done, just hang...");
}

// this is a test function for kernel
fn test_kernel() void {
    var tmp = lib.mem.P_MEM.allocate_page();
    if (tmp != 0) {
        lib.mem.P_MEM.free_page(tmp);
    } else {
        lib.tty.println("allocate memory fails", null);
    }
    // var boot_time = lib.time.UTC2(lib.boot_info.bootTime2UTC(), lib.time.TIME_ZONE.CTorCST);
    // println("boot time is {}-{}-{} {}:{}:{}", .{
    //     boot_time.year,
    //     boot_time.month,
    //     boot_time.day,
    //     boot_time.hour,
    //     boot_time.minute,
    //     boot_time.second,
    // });
    //
    // var time = lib.time.nowTime();
    // println("now time is {}-{}-{} {}:{}:{}", .{
    //     time.year,
    //     time.month,
    //     time.day,
    //     time.hour,
    //     time.minute,
    //     time.second,
    // });
}
