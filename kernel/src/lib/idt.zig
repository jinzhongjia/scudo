// more:https://wiki.osdev.org/Interrupts_Tutorial
// about exception error code https://wiki.osdev.org/Exceptions#Selector_Error_Code
const tty = @import("tty.zig");
const cpu = @import("../cpu.zig");

pub const IRQ_ENUM = PIC.IRQ;
pub const Mask_IRQ = PIC.mask_IRQ;
pub const Register_IRQ = PIC.registerIRQ;

pub fn init() void {
    // We set up the entire idt here to prevent unknown problems.
    inline for (0..idt.len) |index| {
        idt_set_descriptor(index, make_undefined_handle(@intCast(index)), @intFromEnum(FLAGS.interrupt_gate));
    }

    // note: we have set default limit through zig's struct field default value
    idtr.base = @intFromPtr(&idt[0]);

    if (cpu.check_apic()) {
        APIC.init();
    } else {
        PIC.init();
    }

    // use lidt to load idtr
    cpu.lidt(@intFromPtr(&idtr));
    // enable interrupt
    cpu.sti();
}

// this function must be used at comptime
fn make_undefined_handle(comptime num: u8) fn () callconv(.C) void {
    const error_code_list = [_]u8{ 8, 10, 11, 12, 13, 14, 17, 21, 29, 30 };
    return struct {
        fn handle() callconv(.C) void {
            var rbp: usize = cpu.rbp();
            const error_code: ?*usize = for (error_code_list) |value| {
                if (value == num) {
                    rbp += 8;
                    break @ptrFromInt(rbp);
                }
            } else null;

            const rip: *usize = @ptrFromInt(rbp + 8);
            const cs: *usize = @ptrFromInt(rbp + 16);
            const eflags: *usize = @ptrFromInt(rbp + 24);
            const rsp: *usize = @ptrFromInt(rbp + 32);
            const ss: *usize = @ptrFromInt(rbp + 40);

            if (error_code) |value| {
                tty.println("error code is 0x{x}", value.*);
            }

            tty.println(
                \\rip is 0x{x}"
                \\cs is 0x{x}
                \\eflags is 0x{x}
                \\rsp is 0x{x}
                \\ss is 0x{x}
            , .{
                rip.*,
                cs.*,
                eflags.*,
                rsp.*,
                ss.*,
            });
            tty.panicf("An undefined interrupt was triggered, interrupt id is {d}", num);
        }
    }.handle;
}

const GDT_OFFSET_KERNEL_CODE: u16 = 0b0000_0000_0010_1000;

//type for IDTR
//https://wiki.osdev.org/Interrupt_Descriptor_Table#IDTR
const idtr_t = packed struct {
    limit: u16 = @sizeOf(@TypeOf(idt)) - 1,
    base: usize,
};

const FLAGS = enum(u8) {
    interrupt_gate = 0b1000_1110, // 0x8E (p=1, dpl=0b00, type=0b1110 => type_attributes=0b1000_1110=0x8E)
    trap_gate = 0b1000_1111, // 0x8F (p=1, dpl=0b00, type=0b1111 => type_attributes=1000_1111b=0x8F)
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

// Interrupt Vector offsets of exceptions.
const EXCEPTION_0: u8 = 0;
const EXCEPTION_31 = EXCEPTION_0 + 31;

const SYSCALL = 128;

const messages = [_][]const u8{
    "#DE Divide Error",
    "#DB RESERVED",
    "--  NMI Interrupt",
    "#BP Breakpoint",
    "#OF Overflow",
    "#BR BOUND Range Exceeded",
    "#UD Invalid Opcode (Undefined Opcode)",
    "#NM Device Not Available (No Math Coprocessor)",
    "#DF Double Fault",
    "--  Coprocessor Segment Overrun (reserved)",
    "#TS Invalid TSS",
    "#NP Segment Not Present",
    "#SS Stack-Segment Fault",
    "#GP General Protection",
    "#PF Page Fault",
    "--  (Intel reserved. Do not use.)",
    "#MF x87 FPU Floating-Point Error (Math Fault)",
    "#AC Alignment Check",
    "#MC Machine Check",
    "#XF SIMD Floating-Point Exception",
    "#VE Virtualization Exception",
    "#CP Control Protection Exception",
} ++ ([_][]const u8{
    "--  Reserved Interrupt",
} ** 6) ++ [_][]const u8{
    "#HV Hypervisor Injection Exception",
    "#VC VMM Communication Exception",
    "#SX Security Exception",
    "--  Reserved Interrupt",
};

// this is a handlers for interrupts which are installed!
// note: we use compile-time code to initialize an array, that 's cool
var handlers: [48]*const fn () void = init: {
    var initial_value: [48]*const fn () void = undefined;
    inline for (0..48) |index| {
        initial_value[index] = make_unhandled(index);
    }
    break :init initial_value;
};

// TODO: I think this function should be refactored
fn make_unhandled(comptime num: u8) fn () noreturn {
    return struct {
        fn handle() noreturn {
            if (num >= PIC.IRQ_0) {
                tty.panicf(
                    \\IRQ EXCEPTION: {d}
                    \\       VECTOR: 0x{x:0>2}
                    \\        ERROR: 0b{b:0>17}
                    \\       RFLAGS: 0b{b:0>22}
                    \\           CS: 0x{x:0>2}
                    \\          RIP: 0x{x}
                    \\          RSP: 0x{x}
                , .{
                    num - PIC.IRQ_0,
                    num,
                    context.error_code,
                    context.rflags,
                    context.cs,
                    context.rip,
                    context.rsp,
                });
            } else {
                tty.panicf(
                    \\EXCEPTION: {s}
                    \\   VECTOR: 0x{x:0>2}
                    \\    ERROR: 0b{b:0>17}
                    \\   RFLAGS: 0b{b:0>22}
                    \\       CS: 0x{x:0>2}
                    \\      RIP: 0x{x}
                    \\      RSP: 0x{x}
                , .{
                    messages[num],
                    num,
                    context.error_code,
                    context.rflags,
                    context.cs,
                    context.rip,
                    context.rsp,
                });
            }
        }
    }.handle;
}

pub fn register(n: u8, handler: *const fn () void) void {
    handlers[n] = handler;
}

export fn interruptDispatch() void {
    const interrupt_num: u8 = @intCast(context.interrupt_num);

    switch (interrupt_num) {
        EXCEPTION_0...EXCEPTION_31 => {
            handlers[interrupt_num]();
        },
        // this logic should be refactored
        PIC.IRQ_0...PIC.IRQ_15 => {
            const irq: u8 = interrupt_num - PIC.IRQ_0;
            // when handle isr, we maybe meet spurious IRQ
            // more: https://wiki.osdev.org/PIC#Handling_Spurious_IRQs
            const spurious = PIC.spurious_IRQ(irq);
            if (!spurious) {
                handlers[interrupt_num]();
            }
            PIC.EOI(interrupt_num, spurious);
        },
        SYSCALL => {
            tty.println("yes, we meet a syscall", null);
        },
        // Theoretically, it would not happen to reach this point.
        else => unreachable,
    }
}

pub export var context: *volatile Context = undefined;

const Context = packed struct {
    // we will manually push register
    registers: Registers,
    // this will be pushed by macro isrGenerate
    interrupt_num: u64,
    // this will be pushed by macro isrGenerate
    error_code: u64, // note: error_code will only be pushed by hardware interrupt
    // In Long Mode, the error code is padded with zeros to form a 64-bit push, so that it can be popped like any other value.

    // CPU status
    // more you can see:
    // https://blog.nvimer.org/2023/10/03/interrupt-function/
    rip: u64,
    cs: u64,
    rflags: u64,
    rsp: u64, // note: this will only be stored when privilege-level change
    ss: u64, // note: this will only be stored when privilege-level change

};

// note: this registers order is according to hhe following assembly macro pushaq
pub const Registers = packed struct {
    rdi: u64 = 0,
    rsi: u64 = 0,
    rbp: u64 = 0,
    rsp: u64 = 0,
    rbx: u64 = 0,
    rdx: u64 = 0,
    rcx: u64 = 0,
    rax: u64 = 0,
};

/// this struct define allthing about PIC.
/// more:https://wiki.osdev.org/PIC
const PIC = struct {
    /// IO base address for master PIC
    const PIC1 = 0x20;
    /// IO base address for slave PIC
    const PIC2 = 0xA0;

    const PIC1_CMD = PIC1;
    const PIC1_DATA = PIC1 + 1;

    const PIC2_CMD = PIC2;
    const PIC2_DATA = PIC2 + 1;

    // PIC commands:
    /// Read the In-Service Register.
    const ISR_READ = 0x0B;
    /// End of Interrupt.
    const PIC_EOI = 0x20;

    // Initialization Control Words commands.
    const ICW1_INIT = 0x10;
    const ICW1_ICW4 = 0x01;
    const ICW4_8086 = 0x01;

    /// Interrupt Vector offsets of IRQs.
    const IRQ_0 = EXCEPTION_31 + 1; // 0x20 master
    const IRQ_8 = IRQ_0 + 8; // 0x28 slave
    const IRQ_15 = IRQ_0 + 15; // 0x2F

    /// this is enum for PIC port
    const IRQ = enum(u4) {
        CLOCK = 0,
        KEYBOARD = 1,
        CASCADE = 2,
        SERIAL_2 = 3,
        SERIAL_1 = 4,
        PARALLEL_2 = 5,
        FLOPPY = 6,
        PARALLEL_1 = 7,
        RTC = 8,
        REDIRECT = 9,
        MOUSE = 12,
        MATH = 13,
        HARDDISK_1 = 14,
        HARDDISK_2 = 15,
    };

    fn init() void {
        install();
        remap();
    }

    /// initialization for pic and remap the irqs
    /// you may confuse to this, for more, you can see this:https://wiki.osdev.org/PIC#Protected_Mode
    fn remap() void {
        // ICW1: start initialization sequence.
        cpu.outb(PIC1_CMD, ICW1_INIT | ICW1_ICW4);
        cpu.outb(PIC2_CMD, ICW1_INIT | ICW1_ICW4);

        // ICW2: Interrupt Vector offsets of IRQs.
        // we will use this remap the pic's offset
        cpu.outb(PIC1_DATA, IRQ_0);
        cpu.outb(PIC2_DATA, IRQ_8);

        // ICW3: IRQ line 2 to connect master to slave PIC.
        cpu.outb(PIC1_DATA, 1 << 2);
        cpu.outb(PIC2_DATA, 2);

        // ICW4: 80x86 mode.
        cpu.outb(PIC1_DATA, ICW4_8086);
        cpu.outb(PIC2_DATA, ICW4_8086);

        // Mask all IRQs.
        cpu.outb(PIC1_DATA, 0xFF);
        cpu.outb(PIC2_DATA, 0xFF);
    }

    fn EOI(interrupt_n: u8, spurious: bool) void {
        if (interrupt_n >= IRQ_8 and !spurious) {
            cpu.outb(PIC2_CMD, PIC_EOI);
        }
        if (interrupt_n < IRQ_8 and spurious) {
            return;
        }
        cpu.outb(PIC1_CMD, PIC_EOI);
    }

    fn mask_IRQ(irq: IRQ, mask: bool) void {
        const irq_num = @intFromEnum(irq);
        const port: u16 = if (irq_num < 8) @intCast(PIC1_DATA) else @intCast(PIC2_DATA);

        const shift: u3 = @intCast(irq_num % 8);
        const current_mask = cpu.inb(port);

        if (mask) {
            cpu.outb(port, current_mask | (@as(u8, 1) << shift));
        } else {
            cpu.outb(port, current_mask & ~(@as(u8, 1) << shift));
        }
    }

    /// Check whether the fired IRQ was spurious.
    /// more: https://wiki.osdev.org/PIC#Spurious_IRQs
    fn spurious_IRQ(irq: u8) bool {
        if (irq != 7 and irq != 15) {
            return false;
        }

        // default is pic1
        var port: u16 = PIC1_CMD;
        if (irq == 15) {
            port = PIC2_CMD;
        }

        // read ISR
        cpu.outb(port, ISR_READ);
        const in_service = cpu.inb(port);

        return (in_service & (1 << 7)) == 0;
    }

    /// register handle for IRA, this will auto unmask
    fn registerIRQ(irq: IRQ, handle: *const fn () void) void {
        const irq_num = @intFromEnum(irq);

        register(@intCast(IRQ_0 + irq_num), handle);

        mask_IRQ(irq, false);
    }
    // Interrupt Service Routines defined externally in assembly.
    extern fn isr0() void;
    extern fn isr1() void;
    extern fn isr2() void;
    extern fn isr3() void;
    extern fn isr4() void;
    extern fn isr5() void;
    extern fn isr6() void;
    extern fn isr7() void;
    extern fn isr8() void;
    extern fn isr9() void;
    extern fn isr10() void;
    extern fn isr11() void;
    extern fn isr12() void;
    extern fn isr13() void;
    extern fn isr14() void;
    extern fn isr15() void;
    extern fn isr16() void;
    extern fn isr17() void;
    extern fn isr18() void;
    extern fn isr19() void;
    extern fn isr20() void;
    extern fn isr21() void;
    extern fn isr22() void;
    extern fn isr23() void;
    extern fn isr24() void;
    extern fn isr25() void;
    extern fn isr26() void;
    extern fn isr27() void;
    extern fn isr28() void;
    extern fn isr29() void;
    extern fn isr30() void;
    extern fn isr31() void;

    // IRQs
    extern fn isr32() void;
    extern fn isr33() void;
    extern fn isr34() void;
    extern fn isr35() void;
    extern fn isr36() void;
    extern fn isr37() void;
    extern fn isr38() void;
    extern fn isr39() void;
    extern fn isr40() void;
    extern fn isr41() void;
    extern fn isr42() void;
    extern fn isr43() void;
    extern fn isr44() void;
    extern fn isr45() void;
    extern fn isr46() void;
    extern fn isr47() void;
    // syscall
    extern fn isr128() void;

    fn install() void {
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
        // IRQs
        idt_set_descriptor(32, isr32, @intFromEnum(FLAGS.interrupt_gate));
        idt_set_descriptor(33, isr33, @intFromEnum(FLAGS.interrupt_gate));
        idt_set_descriptor(34, isr34, @intFromEnum(FLAGS.interrupt_gate));
        idt_set_descriptor(35, isr35, @intFromEnum(FLAGS.interrupt_gate));
        idt_set_descriptor(36, isr36, @intFromEnum(FLAGS.interrupt_gate));
        idt_set_descriptor(37, isr37, @intFromEnum(FLAGS.interrupt_gate));
        idt_set_descriptor(38, isr38, @intFromEnum(FLAGS.interrupt_gate));
        idt_set_descriptor(39, isr39, @intFromEnum(FLAGS.interrupt_gate));
        idt_set_descriptor(40, isr40, @intFromEnum(FLAGS.interrupt_gate));
        idt_set_descriptor(41, isr41, @intFromEnum(FLAGS.interrupt_gate));
        idt_set_descriptor(42, isr42, @intFromEnum(FLAGS.interrupt_gate));
        idt_set_descriptor(43, isr43, @intFromEnum(FLAGS.interrupt_gate));
        idt_set_descriptor(44, isr44, @intFromEnum(FLAGS.interrupt_gate));
        idt_set_descriptor(45, isr45, @intFromEnum(FLAGS.interrupt_gate));
        idt_set_descriptor(46, isr46, @intFromEnum(FLAGS.interrupt_gate));
        idt_set_descriptor(47, isr47, @intFromEnum(FLAGS.interrupt_gate));
        // syscall
        idt_set_descriptor(128, isr128, @intFromEnum(FLAGS.interrupt_gate));
    }
};

pub const APIC = struct {
    pub fn init() void {
        // TODO: more

        // disable 8259A
        PIC.remap();
    }
};

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
        \\             push $0b10000000000000000
        // 10000
        \\         .endif
        \\         push $\n
        \\         jmp isrCommon
        \\ .endmacro
        \\
        //  this macro function is used to replace pusha in 32-bits instruction
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
        //  this macro function is used to replace pusha in 32-bits instruction
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
        // You may notice that we don't store segment registers
        // The segment registers don't hold any meaningful values in long mode.
        \\    pushaq // Save the registers state.
        \\
        // Save the pointer to the context
        \\    mov %rsp, context
        \\    
        // Handle the interrupt event
        \\    call interruptDispatch
        \\
        // Restore the pointer to the context
        \\    mov context, %rsp
        \\    popaq
        \\    add $16, %rsp 
        \\    iretq
        \\ .type isrCommon, @function
        \\
        // Exceptions.
        \\ isrGenerate 0
        \\ isrGenerate 1
        \\ isrGenerate 2
        \\ isrGenerate 3
        \\ isrGenerate 4
        \\ isrGenerate 5
        \\ isrGenerate 6
        \\ isrGenerate 7
        \\ isrGenerate 8, 1
        \\ isrGenerate 9
        \\ isrGenerate 10, 1
        \\ isrGenerate 11, 1
        \\ isrGenerate 12, 1
        \\ isrGenerate 13, 1
        \\ isrGenerate 14, 1
        \\ isrGenerate 15
        \\ isrGenerate 16
        \\ isrGenerate 17, 1
        \\ isrGenerate 18
        \\ isrGenerate 19
        \\ isrGenerate 20
        \\ isrGenerate 21, 1
        \\ isrGenerate 22
        \\ isrGenerate 23
        \\ isrGenerate 24
        \\ isrGenerate 25
        \\ isrGenerate 26
        \\ isrGenerate 27
        \\ isrGenerate 28
        \\ isrGenerate 29, 1
        \\ isrGenerate 30, 1
        \\ isrGenerate 31
        // IRQs.
        \\ isrGenerate 32
        \\ isrGenerate 33
        \\ isrGenerate 34
        \\ isrGenerate 35
        \\ isrGenerate 36
        \\ isrGenerate 37
        \\ isrGenerate 38
        \\ isrGenerate 39
        \\ isrGenerate 40
        \\ isrGenerate 41
        \\ isrGenerate 42
        \\ isrGenerate 43
        \\ isrGenerate 44
        \\ isrGenerate 45
        \\ isrGenerate 46
        \\ isrGenerate 47
        // syscall
        \\ isrGenerate 128
    );
}
