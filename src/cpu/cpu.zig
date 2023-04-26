pub const x86 = @import("x86/x86.zig");

pub inline fn debug() void {
    asm volatile ("xchgw %bx, %bx");
}
