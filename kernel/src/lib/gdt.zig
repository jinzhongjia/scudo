const tty = @import("tty.zig");
// 定义的是最大的gdt数量
const GDT_SIZE = 128;

// 描述符表条目
const entry = packed struct {
    limit_low: u16,
    base_low: u16,
    base_mid: u8,
    access: u8,
    limit_high: u4,
    flags: u4,
    base_high: u8,
};

// 描述符表选择符
const selector = packed struct {
    RPL: u2,
    TI: u1,
    Index: u13,
};

// 描述符表寄存器
const register = packed struct {
    limit: u16,
    base: u64,
};

fn makeEntry(base: usize, limit: usize, access: u8, flags: u4) entry {
    return entry{
        .limit_low = @truncate(limit),
        .base_low = @truncate(base),
        .base_mid = @truncate(base >> 16),
        .access = @truncate(access),
        .limit_high = @truncate(limit >> 16),
        .flags = @truncate(flags),
        .base_high = @truncate(base >> 24),
    };
}

// 全局描述符表
var gdt = [_]entry{
    makeEntry(0, 0x00000, 0x00, 0x0),
    makeEntry(0, 0xFFFFF, 0x98, 0x4),
    makeEntry(0, 0xFFFFF, 0x9A, 0x0),
    makeEntry(0, 0xFFFFF, 0x92, 0xC),
    makeEntry(0, 0xFFFFF, 0xFA, 0xA),
    makeEntry(0, 0xFFFFF, 0xF2, 0xC),
};

// 全局描述符表寄存器
var gdtr: register = register{
    .limit = @sizeOf(@TypeOf(gdt)) - 1,
    .base = undefined,
};

pub fn init() void {}
