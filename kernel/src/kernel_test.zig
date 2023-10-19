const lib = @import("lib.zig");
const println = lib.tty.println;

/// this is a test function for kernel
pub inline fn test_kernel() void {
    // test for high address for limine
    // need 6G memory
    {
        // var addr: usize = 0xffff_8001_4000_0000;
        // var ptr: *u8 = @ptrFromInt(addr);
        // ptr.* = 5;
        //
        // println("{}", ptr.*);
    }

    // test for bitmaps
    {
        // var bit_buf: [2]u8 = undefined;
        // var bitmap = lib.std.bitmap_t.init(@intFromPtr(&bit_buf), 2, 0);
        // bitmap.set_bit(1, true);
        // if (bitmap.test_bit(1)) {
        //     println("set_bit and test_bit is ok", null);
        // }
        //
        // if (bitmap.scan(2)) |index| {
        //     if (index == 2) {
        //         println("scan is ok", null);
        //     }
        // }
    }

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
