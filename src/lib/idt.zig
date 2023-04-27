const x86 = @import("cpu").x86;
const tty = @import("tty.zig");
const gdt = @import("gdt.zig");
const interrupt = @import("interrupt.zig");

// Types of gates.
const INTERRUPT_GATE = 0x8E;
const SYSCALL_GATE = 0xEE;

// Interrupt Descriptor Table.
var idt: [256]Entry = undefined;

// IDT descriptor register pointing at the IDT.
var idtr = Register{
    .limit = @intCast(u16, @sizeOf(@TypeOf(idt))),
    .base = undefined,
};

// Structure representing an entry in the IDT.
const Entry = packed struct {
    isr_low: u16, // The lower 16 bits of the ISR's address
    kernel_cs: u16, // The GDT segment selector that the CPU will load into CS before calling the ISR
    reserved: u8 = 0, // Set to zero
    flags: u8,
    isr_high: u16,
};

// IDT descriptor register.
const Register = packed struct {
    limit: u16,
    base: usize,
};

////
// Setup an IDT entry.
//
// Arguments:
//     n: Index of the gate.
//     flags: Type and attributes.
//     offset: Address of the ISR.
//
pub fn setGate(n: u8, flags: u8, offset: *const fn () callconv(.C) void) void {
    const intOffset = @ptrToInt(offset);

    idt[n].isr_low = @truncate(u16, intOffset);
    idt[n].isr_high = @truncate(u16, intOffset >> 16);
    idt[n].flags = flags;
    idt[n].reserved = 0;
    idt[n].kernel_cs = gdt.KERNEL_CODE;
}

////
// Initialize the Interrupt Descriptor Table.
//
pub fn initialize() void {
    tty.step("Setting up the Interrupt Descriptor Table", .{});

    // setting the idtr address
    idtr.base = @ptrToInt(&idt);

    // remap the pic
    interrupt.remapPIC();

    // set the correct ISR
    install();

    // reload the idt
    x86.assembly.lidt(@ptrToInt(&idtr));

    tty.stepOK();
}

////
// Install the Interrupt Service Routines in the IDT.
//
pub fn install() void {
    // Exceptions.
    setGate(0, INTERRUPT_GATE, interrupt.isr0);
    setGate(1, INTERRUPT_GATE, interrupt.isr1);
    setGate(2, INTERRUPT_GATE, interrupt.isr2);
    setGate(3, INTERRUPT_GATE, interrupt.isr3);
    setGate(4, INTERRUPT_GATE, interrupt.isr4);
    setGate(5, INTERRUPT_GATE, interrupt.isr5);
    setGate(6, INTERRUPT_GATE, interrupt.isr6);
    setGate(7, INTERRUPT_GATE, interrupt.isr7);
    setGate(8, INTERRUPT_GATE, interrupt.isr8);
    setGate(9, INTERRUPT_GATE, interrupt.isr9);
    setGate(10, INTERRUPT_GATE, interrupt.isr10);
    setGate(11, INTERRUPT_GATE, interrupt.isr11);
    setGate(12, INTERRUPT_GATE, interrupt.isr12);
    setGate(13, INTERRUPT_GATE, interrupt.isr13);
    setGate(14, INTERRUPT_GATE, interrupt.isr14);
    setGate(15, INTERRUPT_GATE, interrupt.isr15);
    setGate(16, INTERRUPT_GATE, interrupt.isr16);
    setGate(17, INTERRUPT_GATE, interrupt.isr17);
    setGate(18, INTERRUPT_GATE, interrupt.isr18);
    setGate(19, INTERRUPT_GATE, interrupt.isr19);
    setGate(20, INTERRUPT_GATE, interrupt.isr20);
    setGate(21, INTERRUPT_GATE, interrupt.isr21);
    setGate(22, INTERRUPT_GATE, interrupt.isr22);
    setGate(23, INTERRUPT_GATE, interrupt.isr23);
    setGate(24, INTERRUPT_GATE, interrupt.isr24);
    setGate(25, INTERRUPT_GATE, interrupt.isr25);
    setGate(26, INTERRUPT_GATE, interrupt.isr26);
    setGate(27, INTERRUPT_GATE, interrupt.isr27);
    setGate(28, INTERRUPT_GATE, interrupt.isr28);
    setGate(29, INTERRUPT_GATE, interrupt.isr29);
    setGate(30, INTERRUPT_GATE, interrupt.isr30);
    setGate(31, INTERRUPT_GATE, interrupt.isr31);

    // IRQs.
    setGate(32, INTERRUPT_GATE, interrupt.isr32);
    setGate(33, INTERRUPT_GATE, interrupt.isr33);
    setGate(34, INTERRUPT_GATE, interrupt.isr34);
    setGate(35, INTERRUPT_GATE, interrupt.isr35);
    setGate(36, INTERRUPT_GATE, interrupt.isr36);
    setGate(37, INTERRUPT_GATE, interrupt.isr37);
    setGate(38, INTERRUPT_GATE, interrupt.isr38);
    setGate(39, INTERRUPT_GATE, interrupt.isr39);
    setGate(40, INTERRUPT_GATE, interrupt.isr40);
    setGate(41, INTERRUPT_GATE, interrupt.isr41);
    setGate(42, INTERRUPT_GATE, interrupt.isr42);
    setGate(43, INTERRUPT_GATE, interrupt.isr43);
    setGate(44, INTERRUPT_GATE, interrupt.isr44);
    setGate(45, INTERRUPT_GATE, interrupt.isr45);
    setGate(46, INTERRUPT_GATE, interrupt.isr46);
    setGate(47, INTERRUPT_GATE, interrupt.isr47);

    // Syscalls.
    setGate(128, SYSCALL_GATE, interrupt.isr128);
}
