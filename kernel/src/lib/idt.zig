/// more:https://wiki.osdev.org/Interrupts_Tutorial
const tty = @import("tty.zig");
const cpu = @import("../cpu.zig");

pub fn init() void {
    // note: we have set default limit through zig's struct field default value
    idtr.base = @intFromPtr(&idt[0]);

    {
        idt_set_descriptor(0, isr0, @intFromEnum(FLAGS.interrupt_gate));
        idt_set_descriptor(1, isr1, @intFromEnum(FLAGS.interrupt_gate));
        idt_set_descriptor(2, isr2, @intFromEnum(FLAGS.interrupt_gate));
        idt_set_descriptor(3, isr3, @intFromEnum(FLAGS.interrupt_gate));
        idt_set_descriptor(4, isr4, @intFromEnum(FLAGS.interrupt_gate));
        idt_set_descriptor(5, isr5, @intFromEnum(FLAGS.interrupt_gate));
        idt_set_descriptor(6, isr6, @intFromEnum(FLAGS.interrupt_gate));
        idt_set_descriptor(7, isr7, @intFromEnum(FLAGS.interrupt_gate));
        idt_set_descriptor(8, isr8, @intFromEnum(FLAGS.interrupt_gate));
        idt_set_descriptor(9, isr9, @intFromEnum(FLAGS.interrupt_gate));
        idt_set_descriptor(10, isr10, @intFromEnum(FLAGS.interrupt_gate));
        idt_set_descriptor(11, isr11, @intFromEnum(FLAGS.interrupt_gate));
        idt_set_descriptor(12, isr12, @intFromEnum(FLAGS.interrupt_gate));
        idt_set_descriptor(13, isr13, @intFromEnum(FLAGS.interrupt_gate));
        idt_set_descriptor(14, isr14, @intFromEnum(FLAGS.interrupt_gate));
        idt_set_descriptor(15, isr15, @intFromEnum(FLAGS.interrupt_gate));
        idt_set_descriptor(16, isr16, @intFromEnum(FLAGS.interrupt_gate));
        idt_set_descriptor(17, isr17, @intFromEnum(FLAGS.interrupt_gate));
        idt_set_descriptor(18, isr18, @intFromEnum(FLAGS.interrupt_gate));
        idt_set_descriptor(19, isr19, @intFromEnum(FLAGS.interrupt_gate));
        idt_set_descriptor(20, isr20, @intFromEnum(FLAGS.interrupt_gate));
        idt_set_descriptor(21, isr21, @intFromEnum(FLAGS.interrupt_gate));
        idt_set_descriptor(22, isr22, @intFromEnum(FLAGS.interrupt_gate));
        idt_set_descriptor(23, isr23, @intFromEnum(FLAGS.interrupt_gate));
        idt_set_descriptor(24, isr24, @intFromEnum(FLAGS.interrupt_gate));
        idt_set_descriptor(25, isr25, @intFromEnum(FLAGS.interrupt_gate));
        idt_set_descriptor(26, isr26, @intFromEnum(FLAGS.interrupt_gate));
        idt_set_descriptor(27, isr27, @intFromEnum(FLAGS.interrupt_gate));
        idt_set_descriptor(28, isr28, @intFromEnum(FLAGS.interrupt_gate));
        idt_set_descriptor(29, isr29, @intFromEnum(FLAGS.interrupt_gate));
        idt_set_descriptor(30, isr30, @intFromEnum(FLAGS.interrupt_gate));
        idt_set_descriptor(31, isr31, @intFromEnum(FLAGS.interrupt_gate));
    }

    cpu.lidt(@intFromPtr(&idtr));
    cpu.sti();
}

const GDT_OFFSET_KERNEL_CODE: u16 = 0b0000_0000_0010_1000;

//type for IDTR
//https://wiki.osdev.org/Interrupt_Descriptor_Table#IDTR
const idtr_t = packed struct {
    limit: u16 = @sizeOf(@TypeOf(idt)) - 1,
    base: usize,
};

const FLAGS = enum(u8) {
    interrupt_gate = 0b1000_1110,
    trap_gate = 0b1000_1111,
};

// type for IDT
// more: https://wiki.osdev.org/Interrupt_Descriptor_Table#Gate_Descriptor_2
const idt_entry_t = packed struct {
    isr_low: u16, // offset bits 0..15
    selector: u16 = GDT_OFFSET_KERNEL_CODE, // a code segment selector in GDT or LDT
    ist: u8 = 0, // bits 0..2 holds Interrupt Stack Table offset, rest of bits zero.
    type_attributes: u8, // gate type, dpl, and p fields
    // Interrupt Gate: 0x8E (p=1, dpl=0b00, type=0b1110 => type_attributes=0b1000_1110=0x8E)
    // Trap Gate: 0x8F (p=1, dpl=0b00, type=0b1111 => type_attributes=1000_1111b=0x8F)
    isr_middle: u16, // offset bits 16..31
    isr_high: u32, // offset bits 32..63
    zero: u32 = 0, // reserved
};

// idt
var idt: [256]idt_entry_t = undefined;

// idtr
var idtr: idtr_t = .{
    .base = 0,
};

fn idt_set_descriptor(vector: u8, isr: *const fn () callconv(.C) void, flags: u8) void {
    const ptr_int = @intFromPtr(isr);

    idt[vector] = idt_entry_t{
        .isr_low = @truncate(ptr_int & 0xFFFF),
        .type_attributes = flags,
        .isr_middle = @truncate((ptr_int >> 16) & 0xFFFF),
        .isr_high = @truncate((ptr_int >> 32) & 0xFFFFFFFF),
    };
}

export fn exception_handler() void {
    @panic("An exception occurred");
}

comptime {
    asm (
    // Template for the Interrupt Service Routines.
        \\ .macro isrGenerate n ec=0
        \\     .align 4
        \\     .type isr\n, @function
        \\ 
        \\     isr\n:
        // Push a dummy error code for interrupts that don't have one.
        \\         .if 1 - \ec
        \\             push $0
        \\         .endif
        \\         push $\n
        \\         jmp isrCommon
        \\ .endmacro
        \\
        \\ .macro pushaq
        \\     push %rax
        \\     push %rcx
        \\     push %rdx
        \\     push %rbx
        \\     push %rsp
        \\     push %rbp
        \\     push %rsi
        \\     push %rdi
        \\ .endm # pushaq
        \\
        \\ .macro popaq
        \\     pop %rdi
        \\     pop %rsi
        \\     pop %rbp
        \\     pop %rsp
        \\     pop %rbx
        \\     pop %rdx
        \\     pop %rcx
        \\     pop %rax
        \\ .endm # popaq
        \\
        \\ isrCommon:
        \\    pushaq // Save the registers state.
        \\    popaq
        \\    add $16, %esp 
        \\    iretq
        \\ .type isrCommon, @function
        \\
        \\ isrGenerate 0
        \\ isrGenerate 1
        \\ isrGenerate 2
        \\ isrGenerate 3
        \\ isrGenerate 4
        \\ isrGenerate 5
        \\ isrGenerate 6
        \\ isrGenerate 7
        \\ isrGenerate 8
        \\ isrGenerate 9
        \\ isrGenerate 10
        \\ isrGenerate 11
        \\ isrGenerate 12
        \\ isrGenerate 13
        \\ isrGenerate 14
        \\ isrGenerate 15
        \\ isrGenerate 16
        \\ isrGenerate 17
        \\ isrGenerate 18
        \\ isrGenerate 19
        \\ isrGenerate 20
        \\ isrGenerate 21
        \\ isrGenerate 22
        \\ isrGenerate 23
        \\ isrGenerate 24
        \\ isrGenerate 25
        \\ isrGenerate 26
        \\ isrGenerate 27
        \\ isrGenerate 28
        \\ isrGenerate 29
        \\ isrGenerate 30
        \\ isrGenerate 31
    );
}

// Interrupt Service Routines defined externally in assembly.
pub extern fn isr0() void;
pub extern fn isr1() void;
pub extern fn isr2() void;
pub extern fn isr3() void;
pub extern fn isr4() void;
pub extern fn isr5() void;
pub extern fn isr6() void;
pub extern fn isr7() void;
pub extern fn isr8() void;
pub extern fn isr9() void;
pub extern fn isr10() void;
pub extern fn isr11() void;
pub extern fn isr12() void;
pub extern fn isr13() void;
pub extern fn isr14() void;
pub extern fn isr15() void;
pub extern fn isr16() void;
pub extern fn isr17() void;
pub extern fn isr18() void;
pub extern fn isr19() void;
pub extern fn isr20() void;
pub extern fn isr21() void;
pub extern fn isr22() void;
pub extern fn isr23() void;
pub extern fn isr24() void;
pub extern fn isr25() void;
pub extern fn isr26() void;
pub extern fn isr27() void;
pub extern fn isr28() void;
pub extern fn isr29() void;
pub extern fn isr30() void;
pub extern fn isr31() void;
