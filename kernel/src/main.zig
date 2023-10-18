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

/// this is a test function for kernel
fn test_kernel() void {
    // test for page fault
    {
        // var num: usize = 0xffff_ffff_f000_0000;
        // var ptr: *u64 = @ptrFromInt(num);
        // ptr.* = 5;
    }

    // test for physical memory allocate
    {
        // var tmp = lib.mem.P_MEM.allocate_page();
        // if (tmp != 0) {
        //     println("allocate physical memory, addr is: 0x{x}", tmp);
        //     lib.mem.P_MEM.free_page(tmp);
        // } else {
        //     println("allocate memory fails", null);
        // }
    }

    // test for boot time
    {
        // var boot_time = lib.time.UTC2(lib.boot_info.bootTime2UTC(), lib.time.TIME_ZONE.CTorCST);
        // println("boot time is {}-{}-{} {}:{}:{}", .{
        //     boot_time.year,
        //     boot_time.month,
        //     boot_time.day,
        //     boot_time.hour,
        //     boot_time.minute,
        //     boot_time.second,
        // });
    }

    // test for now time
    {
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
}
