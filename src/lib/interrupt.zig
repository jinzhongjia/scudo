const tty = @import("tty.zig");
const syscall = @import("syscall.zig");
const ipc = @import("ipc.zig");
const x86 = @import("cpu").x86;
// some declare about PIC 8259
// About more, you can see these:
// https://wiki.osdev.org/PIC
// more detail:
// https://en.wikibooks.org/wiki/assembly_Assembly/Programmable_Interrupt_Controller

// PIC is the 8259 Programmable Interrupt Controller,
// Without it, the assembly architecture would not be an interrupt driven architecture
// The function of the 8259A is to manage hardware interrupts and send them to the appropriate system interrupt.
//
// About more, can see https://wiki.osdev.org/PIC#The_IBM_PC.2FAT_8259_PIC_Architecture

// PIC ports.
const PIC1_CMD = 0x20;
const PIC1_DATA = 0x21;
const PIC2_CMD = 0xA0;
const PIC2_DATA = 0xA1;

var irq_subscribers = []ipc.MailboxId{ipc.MailboxId.Kernel} ** 16;

// PIC command.
// This is issued to the PIC chips at the end of an IRQ-based interrupt routine.
// If the IRQ came from the Master PIC,
// it is sufficient to issue this command only to the Master PIC;
// however if the IRQ came from the Slave PIC,
// it is necessary to issue the command to both PIC chips.
//
const PIC_EOI = 0x20; // end of interrupt (EOI)
const ISR_READ = 0x0B; // Read the In-Service Register.

// Initialization Control Words commands.
const ICW1_INIT = 0x10; // Initialization - required!
const ICW1_ICW4 = 0x01; // Indicates that ICW4 will be present
const ICW4_8086 = 0x01; // 8086/88 (MCS-80/85) mode

// Interrupt Vector offsets of exceptions.
pub const EXCEPTION_0 = 0;
pub const EXCEPTION_31 = EXCEPTION_0 + 31;
// Interrupt Vector offsets of IRQs.
pub const IRQ_0 = EXCEPTION_31 + 1;
pub const IRQ_15 = IRQ_0 + 15;
// Interrupt Vector offsets of syscalls.
pub const SYSCALL = 128;

// Registered interrupt handlers.
// pub var handlers: [48]*const fn () void = undefined;
// Registered interrupt handlers.
pub var handlers = [_]*const fn () void{unhandled} ** 48;

// Pointer to the current saved context.
pub export var context: *volatile Context = undefined;

////
// Default interrupt handler.
//
fn unhandled() noreturn {
    const n = context.interrupt_n;
    if (n >= IRQ_0) {
        tty.panic("Unhandled IRQ number {d}", .{n - IRQ_0});
    } else {
        tty.panic("Unhandled exception number {d}", .{n});
    }
    x86.assembly.hang();
}

////
// Call the correct handler based on the interrupt number.
//
export fn interruptDispatch() void {
    const n = @intCast(u8, context.interrupt_n);

    switch (n) {
        // Exceptions.
        EXCEPTION_0...EXCEPTION_31 => {
            handlers[n]();
        },

        // IRQs.
        IRQ_0...IRQ_15 => {
            const irq = n - IRQ_0;
            if (spuriousIRQ(irq)) return;

            handlers[n]();
            endOfInterrupt(irq);
        },

        // Syscalls.
        SYSCALL => {
            // TODO:syscall
            const syscall_n = context.registers.eax;
            // tty.print("A syscall comes, id: {d}", .{syscall_n});
            // const syscall_n = isr.context.registers.eax;
            if (syscall_n < syscall.handlers.len) {
                syscall.handlers[syscall_n]();
            } else {
                syscall.invalid();
            }
        },

        else => {
            tty.panic("sorry, meet unknown interrupt id", .{});
        },
    }

    // TODO:this is when no thread to run
    // If no user thread is ready to run, halt here and wait for interrupts.
    // if (scheduler.current() == null) {
    //     x86.sti();
    //     x86.hlt();
    // }
    // tty.panic("Here in not handle!", .{});
    // x86.assembly.sti();
    // x86.assembly.hlt();
}

////
// Remap the PICs so that IRQs don't override software interrupts.
//
pub fn remapPIC() void {
    // ICW1: start initialization sequence.
    x86.assembly.outb(PIC1_CMD, ICW1_INIT | ICW1_ICW4);
    x86.assembly.outb(PIC2_CMD, ICW1_INIT | ICW1_ICW4);

    // ICW2: Interrupt Vector offsets of IRQs.
    x86.assembly.outb(PIC1_DATA, IRQ_0); // IRQ 0..7  -> Interrupt 32..39
    x86.assembly.outb(PIC2_DATA, IRQ_0 + 8); // IRQ 8..15 -> Interrupt 40..47

    // ICW3: IRQ line 2 to connect master to slave PIC.
    x86.assembly.outb(PIC1_DATA, 1 << 2);
    x86.assembly.outb(PIC2_DATA, 2);

    // ICW4: 80assembly mode.
    x86.assembly.outb(PIC1_DATA, ICW4_8086);
    x86.assembly.outb(PIC2_DATA, ICW4_8086);

    // Mask all IRQs.
    x86.assembly.outb(PIC1_DATA, 0xFF);
    x86.assembly.outb(PIC2_DATA, 0xFF);
}

////
// Check whether the fired IRQ was spurious.
//
// Arguments:
//     irq: The number of the fired IRQ.
//
// Returns:
//     true if the IRQ was spurious, false otherwise.
//
pub inline fn spuriousIRQ(irq: u8) bool {
    // Only IRQ 7 and IRQ 15 can be spurious.
    if (irq != 7) return false;
    // TODO: handle spurious IRQ15.

    // Read the value of the In-Service Register.
    x86.assembly.outb(PIC1_CMD, ISR_READ);
    const in_service = x86.assembly.inb(PIC1_CMD);

    // Verify whether IRQ7 is set in the ISR.
    return (in_service & (1 << 7)) == 0;
}

////
// Signal the end of the IRQ interrupt routine to the PICs.
//
// Arguments:
//     irq: The number of the IRQ being handled.
//
pub inline fn endOfInterrupt(irq: u8) void {
    if (irq >= 8) {
        // Signal to the Slave PIC.
        x86.assembly.outb(PIC2_CMD, PIC_EOI);
    }
    // Signal to the Master PIC.
    x86.assembly.outb(PIC1_CMD, PIC_EOI);
}

////
// Register an interrupt handler.
//
// Arguments:
//     n: Index of the interrupt.
//     handler: Interrupt handler.
//
pub fn register(n: u8, handler: *const fn () void) void {
    handlers[n] = handler;
}

////
// Register an IRQ handler.
//
// Arguments:
//     irq: Index of the IRQ.
//     handler: IRQ handler.
//
pub fn registerIRQ(irq: u8, handler: *const fn () void) void {
    register(IRQ_0 + irq, handler);
    maskIRQ(irq, false); // Unmask the IRQ.
}

////
// Mask/unmask an IRQ.
//
// Arguments:
//     irq: Index of the IRQ.
//     mask: Whether to mask (true) or unmask (false).
//
pub fn maskIRQ(irq: u8, mask: bool) void {
    // Figure out if master or slave PIC owns the IRQ.
    const port = if (irq < 8) @intCast(u16, PIC1_DATA) else @intCast(u16, PIC2_DATA);
    const old = x86.assembly.inb(port); // Retrieve the current mask.

    // Mask or unmask the interrupt.
    const shift = @intCast(u3, irq % 8);
    if (mask) {
        x86.assembly.outb(port, old | (@intCast(u8, 1) << shift));
    } else {
        x86.assembly.outb(port, old & ~(@intCast(u8, 1) << shift));
    }
}

////
// Subscribe to an IRQ. Every time it fires, the kernel
// will send a message to the given mailbox.
//
// Arguments:
//     irq: Number of the IRQ to subscribe to.
//     mailbox_id: Mailbox to send the message to.
//
pub fn subscribeIRQ(irq: u8, mailbox_id: *const ipc.MailboxId) void {
    // TODO: validate.
    irq_subscribers[irq] = mailbox_id.*;
    registerIRQ(irq, notifyIRQ);
}

////
// Notify the subscribed thread that the IRQ of interest has fired.
//
fn notifyIRQ() void {
    const irq = context.interrupt_n - IRQ_0;
    const subscriber = irq_subscribers[irq];

    switch (subscriber) {
        ipc.MailboxId.Port => {
            ipc.send(&(ipc.Message.to(subscriber, 0, irq)
                .as(ipc.MailboxId.Kernel)));
        },
        else => unreachable,
    }
    // TODO: support other types of mailboxes.
}

pub const Registers = packed struct {
    edi: u32 = 0,
    esi: u32 = 0,
    ebp: u32 = 0,
    esp: u32 = 0,
    ebx: u32 = 0,
    edx: u32 = 0,
    ecx: u32 = 0,
    eax: u32 = 0,
};

// Context saved by Interrupt Service Routines.
pub const Context = packed struct {
    registers: Registers, // General purpose registers.

    interrupt_n: u32, // Number of the interrupt.
    error_code: u32, // Associated error code (or 0).

    // for now , we will only use registers, interrupt_n, error_code

    // CPU status:
    eip: u32,
    cs: u32,
    eflags: u32,
    esp: u32,
    ss: u32,

    pub inline fn setReturnValue(self: *volatile Context, value: anytype) void {
        self.registers.eax = if (@TypeOf(value) == bool) @boolToInt(value) else @intCast(u32, value);
    }
};

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
pub extern fn isr32() void;
pub extern fn isr33() void;
pub extern fn isr34() void;
pub extern fn isr35() void;
pub extern fn isr36() void;
pub extern fn isr37() void;
pub extern fn isr38() void;
pub extern fn isr39() void;
pub extern fn isr40() void;
pub extern fn isr41() void;
pub extern fn isr42() void;
pub extern fn isr43() void;
pub extern fn isr44() void;
pub extern fn isr45() void;
pub extern fn isr46() void;
pub extern fn isr47() void;
pub extern fn isr128() void;

comptime {
    asm (
        \\ // Kernel stack for interrupt handling.
        \\ KERNEL_STACK = 0x80000
        \\ // GDT selectors.
        \\ KERNEL_DS = 0x10
        \\ USER_DS   = 0x23
        \\ 
        \\ // Template for the Interrupt Service Routines.
        \\ .macro isrGenerate n
        \\     .align 4
        \\     .type isr\n, @function
        \\ 
        \\     isr\n:
        \\         // Push a dummy error code for interrupts that don't have one.
        \\         .if (\n != 8 && !(\n >= 10 && \n <= 14) && \n != 17)
        \\             push $0
        \\         .endif
        \\         push $\n       // Push the interrupt number.
        \\         jmp isrCommon  // Jump to the common handler.
        \\ .endmacro
        \\ 
        \\ // Common code for all Interrupt Service Routines.
        \\ isrCommon:
        \\     pusha  // Save the registers state.
        \\     mov %esp, context
        \\
        \\     mov %ds,%eax
        \\     pushl %eax
        \\ 
        // \\     // Setup kernel data segment.
        \\     mov $KERNEL_DS, %ax
        \\     mov %ax, %ds
        \\     mov %ax, %es
        \\     mov %ax, %fs
        \\     mov %ax, %gs
        \\     mov %ax, %ss
        \\ 
        \\     // Save the pointer to the current context and switch to the kernel stack.
        // \\     mov $KERNEL_STACK, %esp
        \\ 
        \\     call interruptDispatch  // Handle the interrupt event.
        \\ 
        \\     // Restore the pointer to the context (of a different thread, potentially).
        // \\     mov context, %esp
        \\     pop %eax      
        \\     mov %eax, %ds
        \\     mov %eax, %es
        \\     mov %eax, %fs
        \\     mov %eax, %gs
        \\     mov %eax, %ss
        \\ 
        \\     // Setup user data segment.
        // \\     mov $USER_DS, %ax
        // \\     mov %ax, %ds
        // \\     mov %ax, %es
        \\ 
        \\     popa          // Restore the registers state.
        \\     add $8, %esp  // Remove interrupt number and error code from stack.
        \\     iret
        \\ .type isrCommon, @function
        \\ 
        \\ // Exceptions.
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
        \\ 
        \\ // IRQs.
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
        \\ 
        \\ // Syscalls.
        \\ isrGenerate 128
    );
}
