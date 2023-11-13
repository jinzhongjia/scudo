const builtin = @import("builtin");
const lib = @import("lib.zig");
const cpu = @import("cpu.zig");
const std = @import("std");
const println = lib.tty.println;

const log = lib.log.scoped(.scudo);

/// this is a test function for kernel
pub inline fn test_kernel() void {
    log.debug("build mode {s}", @tagName(builtin.mode));

    if (false) {
        var lock = cpu.SpinLock{};
        lock.acquire();
        // NOTE: this will block
        lock.acquire();
        lock.release();
    }

    // println("0x{x}", cpu.IA32_APIC_BASE.read().getAddress());
    // asm volatile ("int $66");

    // test v mem map
    if (false) {
        var vaddr: usize = 0xf0003000;
        // const paddr = lib.mem.P_MEM.allocate_page();
        const paddr = 0x6000;
        lib.mem.V_MEM.map(paddr, vaddr, .small);

        var ptr: *u8 = @ptrFromInt(vaddr);
        println("virtual address of 0x{x} is {}", .{ vaddr, ptr.* });
    }

    // test for Virtual_Addr translate
    if (false) {
        const addr = 0xffff_8000_0001_0000;
        var result = lib.mem.V_MEM.translate_virtual_address(addr);
        if (result) |val| {
            if (val != 0x10000) {
                println("test virtual addr translate fails, 0x{x}", val);
            } else {
                println("test for virtual addr translate is ok", null);
            }
        } else {
            println("test virtual addr translate fails, return val is null", null);
        }
    }

    // test for high address for limine
    // need 6G memory
    if (false) {
        var addr: usize = 0xffff_8001_4000_0000;
        var ptr: *u8 = @ptrFromInt(addr);
        ptr.* = 5;

        println("{}", ptr.*);
    }

    // test for bitmaps
    if (false) {
        var bit_buf: [2]u8 = undefined;
        var bitmap = lib.stdlib.bitmap_t.init(@intFromPtr(&bit_buf), 2, 0);
        bitmap.set_bit(1, true);
        if (bitmap.test_bit(1)) {
            println("set_bit and test_bit is ok", null);
        }

        if (bitmap.scan(2)) |index| {
            if (index == 2) {
                println("scan is ok", null);
            }
        }
    }

    // test for page fault
    if (false) {
        var num: usize = 0xffff_ffff_f000_0000;
        var ptr: *u64 = @ptrFromInt(num);
        ptr.* = 5;
    }

    // test for physical memory allocate
    if (false) {
        println("{}", lib.mem.P_MEM.get_free_pages());
        var tmp = lib.mem.P_MEM.allocate_page();
        println("{}", lib.mem.P_MEM.get_free_pages());
        var tmp1 = lib.mem.P_MEM.allocate_page();
        println("{}", lib.mem.P_MEM.get_free_pages());
        var tmp2 = lib.mem.P_MEM.allocate_page();
        println("{}", lib.mem.P_MEM.get_free_pages());
        if (tmp == tmp1) {
            println("allocate_page test fails", null);
        } else {
            if (tmp != 0) {
                println("allocate physical memory, addr is: 0x{x}", tmp);
                println("allocate physical memory, addr is: 0x{x}", tmp1);
                println("allocate physical memory, addr is: 0x{x}", tmp2);
                lib.mem.P_MEM.free_page(tmp);
                println("{}", lib.mem.P_MEM.get_free_pages());
                lib.mem.P_MEM.free_page(tmp1);
                println("{}", lib.mem.P_MEM.get_free_pages());
                lib.mem.P_MEM.free_page(tmp2);
                println("{}", lib.mem.P_MEM.get_free_pages());
            } else {
                println("allocate memory fails", null);
            }
        }
    }

    // test for boot time
    if (false) {
        var boot_time = lib.time.UTC2(lib.boot_info.bootTime2UTC(), lib.time.TIME_ZONE.CTorCST);
        println("boot time is {}-{}-{} {}:{}:{}", .{
            boot_time.year,
            boot_time.month,
            boot_time.day,
            boot_time.hour,
            boot_time.minute,
            boot_time.second,
        });
    }

    // test for now time
    if (false) {
        var time = lib.time.nowTime();
        println("now time is {}-{}-{} {}:{}:{}", .{
            time.year,
            time.month,
            time.day,
            time.hour,
            time.minute,
            time.second,
        });
    }
}
