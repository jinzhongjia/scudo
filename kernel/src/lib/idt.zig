// more:https://wiki.osdev.org/Interrupts_Tutorial
// about exception error code https://wiki.osdev.org/Exceptions#Selector_Error_Code
const std = @import("std");
const tty = @import("tty.zig");
const config = @import("config");
const cpu = @import("../cpu.zig");
const mem = @import("mem.zig");
const log = @import("../lib.zig").log;

pub fn Mask_VECTOR(vector: u8, mask: bool) void {
    if (is_apic) {
        switch (vector) {
            0...0x1f => {},
            PIC.IRQ_0...PIC.IRQ_15 => {
                const irq_num = vector - PIC.IRQ_0;
                for (APIC.override_list) |value| {
                    if (value.irq_source == irq_num) {
                        APIC.mask_gsi(value.gsi, mask);
                        return;
                    }
                }
            },
            else => {
                APIC.mask_gsi(vector, mask);
            },
        }
    } else {
        PIC.mask_IRQ(vector - PIC.IRQ_0, mask);
    }
}

var is_apic: bool = undefined;

// Registered functions exposed to the outside world
pub fn registerInterruptHandle(vector: u8, handle: *const fn () void) void {
    if (is_apic) {
        APIC.registerIRQ(vector, handle);
    } else {
        PIC.registerIRQ(vector, handle);
    }
}

pub fn init() void {

    // note: we have set default limit through zig's struct field default value
    idtr.base = @intFromPtr(&idt[0]);

    inline for (0..idt.len) |index| {
        idt_set_descriptor(index, generate_handle(@intCast(index)), @intFromEnum(FLAGS.interrupt_gate));
    }

    PIC.remap();

    if (config.enable_APIC and cpu.check_apic()) {
        if (cpu.x2APIC_available()) {
            log.info("init x2APIC", null);
        } else {
            log.info("init APIC", null);
        }
        is_apic = true;
        APIC.init();
    } else {
        is_apic = false;
        log.info("init 8259A_PIC", null);
    }

    // use lidt to load idtr
    cpu.lidt(@intFromPtr(&idtr));
    // enable interrupt
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

fn idt_set_descriptor(vector: u8, isr: *const fn () callconv(.Naked) void, flags: u8) void {
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

const SYSCALL = 0x80;

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

const handlers_len = 256;
// this is a handlers for interrupts which are installed!
// note: we use compile-time code to initialize an array, that 's cool
var handlers: [handlers_len]?*const fn () void = init: {
    var initial_value: [handlers_len]?*const fn () void = undefined;
    inline for (0..handlers_len) |index| {
        initial_value[index] = null;
    }
    break :init initial_value;
};

// TODO:this function should be privited
fn register_handle(n: u8, handler: *const fn () void) void {
    handlers[n] = handler;
}

export fn interruptDispatch() void {
    const interrupt_num: u8 = @intCast(context.interrupt_num);

    switch (interrupt_num) {
        EXCEPTION_0...EXCEPTION_31 => {
            if (handlers[interrupt_num]) |fun| {
                fun();
            } else {
                log.err("EXCEPTION_{} is not registered", interrupt_num);
                cpu.stopCPU();
            }
        },
        // this logic should be refactored
        PIC.IRQ_0...PIC.IRQ_15 => {
            if (is_apic) {
                if (interrupt_num != 110) {
                    // handlers[interrupt_num]();
                    if (handlers[interrupt_num]) |fun| {
                        fun();
                        APIC.EOI();
                    } else {
                        log.err("APIC_{} is not registered", interrupt_num);
                        cpu.stopCPU();
                    }
                }
            } else {
                const irq: u8 = interrupt_num - PIC.IRQ_0;
                // when handle isr, we maybe meet spurious IRQ
                // more: https://wiki.osdev.org/PIC#Handling_Spurious_IRQs
                const spurious = PIC.spurious_IRQ(irq);
                if (!spurious) {
                    // handlers[interrupt_num]();
                    if (handlers[interrupt_num]) |fun| {
                        fun();
                    } else {
                        log.err("PIC_IRQ_{} is not registered", interrupt_num);
                        cpu.stopCPU();
                    }
                }
                PIC.EOI(interrupt_num, spurious);
            }
        },
        SYSCALL => {
            tty.println("yes, we meet a syscall", null);
        },
        // Theoretically, it would not happen to reach this point.
        else => {
            if (is_apic) {
                if (interrupt_num != 110) {
                    if (handlers[interrupt_num]) |fun| {
                        fun();
                        APIC.EOI();
                    } else {
                        log.err("APIC_GSI_{} is not registered", interrupt_num);
                        cpu.stopCPU();
                    }
                }
            } else {
                log.err("other_{} is not registered", interrupt_num);
                cpu.stopCPU();
            }
        },
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
const Registers = packed struct {
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

    fn mask_IRQ(irq: u8, mask: bool) void {
        const irq_num = irq;
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
    fn registerIRQ(vector: u8, handle: *const fn () void) void {
        // const irq_num = @intFromEnum(irq);

        register_handle(vector, handle);

        mask_IRQ(vector - IRQ_0, false);
    }
};

const APIC = struct {
    var ia32_apic_base: cpu.IA32_APIC_BASE = undefined;

    var max_lvt_len: u8 = 0;
    var version: APIC_VERSION = undefined;

    var eoi_can_set: bool = undefined;

    pub fn init() void {
        // about setting up apic
        // wen can refer this article, https://blog.wesleyac.com/posts/ioapic-interrupts#fnref1
        local_apic_init();

        parse_RSDP();

        io_apic_init();
    }

    fn EOI() void {
        Register.write_register(Register.EOI, 0);
    }

    const VECTOR_OFFSET = 0x30;
    fn registerIRQ(vector: u8, handle: *const fn () void) void {
        switch (vector) {
            0...0x1f => {
                register_handle(vector, handle);
            },
            PIC.IRQ_0...PIC.IRQ_15 => {
                const irq_num = vector - PIC.IRQ_0;
                for (override_list) |value| {
                    if (value.irq_source == irq_num) {
                        register_handle(vector, handle);
                        mask_gsi(value.gsi, false);
                        return;
                    }
                }
            },
            else => {
                register_handle(vector, handle);
                mask_gsi(vector, false);
            },
        }
    }

    fn mask_gsi(gsi: u32, mask: bool) void {
        var val = ioapic_redtbl_read(gsi);
        if (mask) {
            val |= 1 << 16;
        } else {
            val &= ~@as(u64, 1 << 16);
        }
        ioapic_redtbl_write(gsi, val);
    }

    fn local_apic_init() void {
        // TODO: add x2apic support

        ia32_apic_base = cpu.IA32_APIC_BASE.read();

        // hardware enable apic, by set bit11 of IA32_APIC_BASE
        if (!ia32_apic_base.global_enable) {
            ia32_apic_base.global_enable = true;
            ia32_apic_base.write();
        }

        const lapic_version_register = Register.read_register(Register.lapic_version);
        // const lapic_id_register = Register.read_register(Register.lapic_id);
        // log.debug("lapic_id is 0x{x}, lapic_version is {s}, Max LVT Entry: 0x{x}, SVR(Suppress EOI Broadcast): {}", .{
        //     lapic_id_register,
        //     @tagName(version),
        //     max_lvt_len,
        //     eoi_can_set,
        // });

        version = APIC_VERSION.make(lapic_version_register);
        max_lvt_len = @intCast((lapic_version_register >> 16 & 0xff) + 1);
        eoi_can_set = lapic_version_register >> 24 & 0x1 == 1;

        // Register.write_register(.TPR, 0x4 << 4);

        // software enable APIC
        const svr = Register.read_register(Register.SVR);
        // enable SVR apic and disable SVR EOI bit
        Register.write_register(Register.SVR, (((svr & ~@as(u32, 0xff)) | 110) | 0x100) & ~@as(u32, 0x1000));
    }

    var ioAPIC_ver: u32 = undefined;
    fn io_apic_init() void {
        ioAPIC_ver = read_ioapic_register(0x1);
        var rte_num: u8 = @truncate((ioAPIC_ver >> 16) & 0xff);
        // remap gsi
        for (0..rte_num) |value| {
            ioapic_redirect(@intCast(value), 0, null);
        }

        // map gsi to irq through override
        for (override_list) |value| {
            ioapic_redirect(value.gsi, value.flags, value.irq_source);
        }
    }

    const RSDP = struct {
        addr: usize,

        const REVISION = enum {
            v1,
            v2,
        };

        fn init(paddr: usize) RSDP {
            return .{
                .addr = paddr,
            };
        }

        fn signature(self: RSDP) []u8 {
            var tmp_ptr: [*]u8 = @ptrFromInt(self.addr);
            return tmp_ptr[0..8];
        }

        fn OEM_id(self: RSDP) []u8 {
            var tmp_ptr: [*]u8 = @ptrFromInt(self.addr);
            return tmp_ptr[9..15];
        }

        fn get_revision(self: RSDP) ?REVISION {
            var tmp_ptr: [*]u8 = @ptrFromInt(self.addr);
            var tmp_revision = tmp_ptr[15];
            if (tmp_revision == 0) {
                return REVISION.v1;
            }

            if (tmp_revision == 2) {
                return REVISION.v2;
            }

            return null;
        }

        fn checksum(self: RSDP) void {
            var tmp_ptr: [*]u8 = @ptrFromInt(self.addr);

            var sum: u8 = 0;

            if (tmp_ptr[15] == 0) {
                for (tmp_ptr[0..20]) |byte| {
                    sum +%= byte;
                }
            } else if (tmp_ptr[15] == 2) {
                for (tmp_ptr[0..36]) |byte| {
                    sum +%= byte;
                }
            }

            if (sum != 0) {
                tty.panicf("sorry, checksum v2 part failed, sum is {}", sum);
            }
        }

        fn rsdt_addr(self: RSDP) usize {
            var tmp_ptr: *u32 = @ptrFromInt(self.addr + 16);
            return @intCast(tmp_ptr.*);
        }

        fn length(self: RSDP) u32 {
            if (self.get_revision()) |revision| {
                if (revision == .v2) {
                    var tmp_ptr: *u32 = @ptrFromInt(self.addr + 20);
                    return tmp_ptr.*;
                }
            }
            @panic("sorry, rsdp is v1, can't get length");
        }

        fn xsdt_addr(self: RSDP) usize {
            var tmp_ptr: *u32 = @ptrFromInt(self.addr + 24);
            return @intCast(tmp_ptr.*);
        }
    };

    var rsdp: RSDP = undefined;
    fn parse_RSDP() void {
        if (cpu.rsdp_request.response) |response| {
            rsdp = RSDP.init(@intFromPtr(response.address));
        } else {
            @panic("sorry, getting rsdp response failed");
        }

        if (rsdp.get_revision()) |revision| {
            switch (revision) {
                .v1 => {
                    parse_RSDT();
                },
                .v2 => {
                    // TODO: add rsdp v2 handle
                    // add parse for XSDT
                    @panic("now not support RSDP V2");
                },
            }
        } else {
            tty.panicf("rsdp revision is unexpected", null);
        }
    }

    var rsdt: RSDT = undefined;
    fn parse_RSDT() void {
        // TODO: add more parse
        rsdt = RSDT.init(mem.V_MEM.paddr_2_high_half(rsdp.rsdt_addr()));

        var res: bool = false;
        for (rsdt.pointers) |value| {
            var addr: usize = value;
            var tmp = ACPI_SDT_header.init(addr);
            var tmp_arr = "APIC";
            if (std.mem.eql(u8, tmp.signature(), tmp_arr)) {
                madt = MADT.init(mem.V_MEM.paddr_2_high_half(addr));
                parse_MADT();
                break;
            }
        }

        if (res) {
            @panic("sorry, we didn't find MADT in RSDT");
        }
    }

    var madt: MADT = undefined;

    var io_apic_addr: usize = undefined;

    var override_arr: [48]*align(1) MADT.IO_APIC_ISO = undefined;
    var override_list: []*align(1) MADT.IO_APIC_ISO = undefined;

    fn parse_MADT() void {
        var index: u32 = 0;
        var entries = madt.entries;
        var override_num: u8 = 0;
        while (index < madt.entries.len) {
            var addr = @intFromPtr(&entries[index]);

            switch (entries[index]) {
                0 => {
                    var ptr: *align(1) MADT.Local_APIC = @ptrFromInt(addr);
                    _ = ptr;
                    // log.debug("{any}", ptr.*);
                },
                1 => {
                    var ptr: *align(1) MADT.IO_APIC = @ptrFromInt(addr);

                    // important!
                    io_apic_addr =
                        mem.V_MEM.paddr_2_high_half(ptr.io_apic_addr);

                    // log.debug("{any}", ptr.*);
                },
                2 => {
                    var ptr: *align(1) MADT.IO_APIC_ISO = @ptrFromInt(addr);
                    override_arr[override_num] = ptr;
                    override_num += 1;
                    // log.debug("{any}", ptr.*);
                },
                3 => {
                    var ptr: *align(1) MADT.IO_APIC_NMI = @ptrFromInt(addr);
                    _ = ptr;
                    // log.debug("{any}", ptr.*);
                },
                4 => {
                    var ptr: *align(1) MADT.LOCAL_APIC_NMI = @ptrFromInt(addr);
                    _ = ptr;
                    // log.debug("{any}", ptr.*);
                },
                5 => {
                    var ptr: *align(1) MADT.LOCAL_APIC_ADDR_OVERRIDE = @ptrFromInt(addr);
                    _ = ptr;
                    // log.debug("{any}", ptr.*);
                },
                9 => {
                    var ptr: *align(1) MADT.Process_Local_X2APIC = @ptrFromInt(addr);
                    _ = ptr;
                    // log.debug("{any}", ptr.*);
                },
                else => {
                    @panic("unrecognized type");
                },
            }
            index += entries[index + 1];
        }

        override_list = override_arr[0..override_num];
    }

    // TODO: add io apic register
    const IO_APIC_REGISTER = enum(u8) {
        ID = 0x00,
        VERSION = 0x01,
        TBL0_0 = 0x10,
        TBL0_1 = 0x11,
    };

    fn write_ioapic_register(offset: u32, val: u32) void {
        var IOREGSEL: *volatile u32 = @ptrFromInt(io_apic_addr);
        IOREGSEL.* = offset;
        var IOREGWIN: *volatile u32 = @ptrFromInt(io_apic_addr + 0x10);
        IOREGWIN.* = val;
    }

    fn read_ioapic_register(offset: u32) u32 {
        var IOREGSEL: *volatile u32 = @ptrFromInt(io_apic_addr);
        IOREGSEL.* = offset;
        var IOREGWIN: *volatile u32 = @ptrFromInt(io_apic_addr + 0x10);
        return IOREGWIN.*;
    }

    fn ioapic_redtbl_write(gsi: u32, val: u64) void {
        var ioredtbl = gsi * 2 + 0x10;
        write_ioapic_register(ioredtbl, @truncate(val));
        write_ioapic_register(ioredtbl + 1, @truncate(val >> 32));
    }

    fn ioapic_redtbl_read(gsi: u32) u64 {
        var ioredtbl = gsi * 2 + 0x10;
        const low = read_ioapic_register(ioredtbl);
        const high: u64 = read_ioapic_register(ioredtbl + 1);
        return (high << 32) + low;
    }

    fn ioapic_redirect(gsi: u32, flags: u16, irq: ?u8) void {
        var redirection: u64 =
            if (irq) |irq_n|
            irq_n + 0x20
        else
            gsi + 0x30;

        if (flags & 2 != 0)
            redirection |= (1 << 13);
        if (flags & 8 != 0)
            redirection |= (1 << 15);

        redirection |= (1 << 16);

        // current apic target is 0
        ioapic_redtbl_write(gsi, redirection);
    }

    const RSDT = struct {
        header: ACPI_SDT_header,
        pointers: []u32,

        fn init(paddr: usize) RSDT {
            var tmp_header = ACPI_SDT_header.init(paddr);
            var tmp_pointers: []u32 = @as([*]u32, @ptrFromInt(paddr))[9 .. tmp_header.length() / 4];
            return .{
                .header = tmp_header,
                .pointers = tmp_pointers,
            };
        }
    };

    const MADT = struct {
        header: ACPI_SDT_header,
        lapic_address: usize,
        flags: u32,
        entries: []u8,

        fn init(paddr: usize) MADT {
            const tmp_header = ACPI_SDT_header.init(paddr);
            const tmp_addr: *u32 = @ptrFromInt(ACPI_SDT_header.size() + paddr);
            const tmp_flags: *u32 = @ptrFromInt(ACPI_SDT_header.size() + paddr + 4);
            const ptr: [*]u8 = @ptrFromInt(paddr);
            return .{
                .header = tmp_header,
                .lapic_address = tmp_addr.*,
                .flags = tmp_flags.*,
                .entries = ptr[ACPI_SDT_header.size() + 8 .. tmp_header.length()],
            };
        }

        const Local_APIC = packed struct {
            type: u8,
            length: u8,
            process_id: u8,
            apic_id: u8,
            flags: u32,
        };

        const IO_APIC = packed struct {
            type: u8,
            length: u8,
            io_apic_id: u8,
            reserved: u8,
            io_apic_addr: u32,
            gsi_base: u32,
        };

        const IO_APIC_ISO = packed struct {
            type: u8,
            length: u8,
            bus_source: u8,
            irq_source: u8,
            gsi: u32,
            flags: u16,
        };

        const IO_APIC_NMI = packed struct {
            type: u8,
            length: u8,
            NMI_source: u8,
            reserved: u8,
            flags: u16,
            gsi: u32,
        };

        const LOCAL_APIC_NMI = packed struct {
            type: u8,
            length: u8,
            apic_process_id: u8,
            flags: u16,
            LINT: u8, // 0 or 1
        };

        const LOCAL_APIC_ADDR_OVERRIDE = packed struct {
            type: u8,
            length: u8,
            reserved: u16,
            addr_lapic: u64,
        };

        const Process_Local_X2APIC = packed struct {
            type: u8,
            length: u8,
            reserved: u16,
            process_local_x2APIC_id: u32,
            flags: u32,
            apic_id: u32,
        };
    };

    const ACPI_SDT_header = packed struct {
        addr: usize,

        fn init(paddr: usize) ACPI_SDT_header {
            return .{
                .addr = paddr,
            };
        }

        inline fn size() u8 {
            return 36;
        }

        fn signature(self: ACPI_SDT_header) []u8 {
            var tmp_ptr: [*]u8 = @ptrFromInt(self.addr);
            return tmp_ptr[0..4];
        }

        fn length(self: ACPI_SDT_header) u32 {
            var tmp_ptr: *u32 = @ptrFromInt(self.addr + 4);
            return tmp_ptr.*;
        }

        fn revision(self: ACPI_SDT_header) u8 {
            var tmp_ptr: [*]u8 = @ptrFromInt(self.addr);
            return tmp_ptr[5];
        }

        fn checksum(self: ACPI_SDT_header) void {
            var tmp_ptr: [*]u8 = @ptrFromInt(self.addr);
            var sum: u8 = 0;

            for (tmp_ptr[0..36]) |byte| {
                sum +%= byte;
            }

            if (sum != 0) {
                tty.panicf(
                    "sorry, checksum acpi header failed, sum is {}, addr is 0x{x}",
                    sum,
                    self.addr,
                );
            }
        }

        fn OEM_id(self: ACPI_SDT_header) []u8 {
            var tmp_ptr: [*]u8 = @ptrFromInt(self.addr);
            return tmp_ptr[10..16];
        }

        fn OEM_table_id(self: ACPI_SDT_header) []u8 {
            var tmp_ptr: [*]u8 = @ptrFromInt(self.addr);
            return tmp_ptr[16..24];
        }

        fn creator_id(self: ACPI_SDT_header) u32 {
            var tmp_ptr: *u32 = @ptrFromInt(self.addr + 28);
            return tmp_ptr.*;
        }

        fn creator_revision(self: ACPI_SDT_header) u32 {
            var tmp_ptr: *u32 = @ptrFromInt(self.addr + 32);
            return tmp_ptr.*;
        }
    };

    const APIC_VERSION = enum {
        apic_82489DX,
        apic_integrated,

        fn make(value: u32) APIC_VERSION {
            var tmp = value & 0xff;
            if (tmp < 0x10) {
                return APIC_VERSION.apic_82489DX;
            } else if (0x10 <= tmp and tmp <= 0x15) {
                return APIC_VERSION.apic_integrated;
            }

            @panic("can't identify the apic version");
        }
    };

    const Register = enum(u16) {
        lapic_id = 0x020,
        lapic_version = 0x030,
        TPR = 0x080,
        APR = 0x090,
        PPR = 0x0A0,
        EOI = 0x0B0,
        RRD = 0x0C0,
        LDR = 0x0D0,
        DFR = 0x0E0,
        SVR = 0x0F0,

        ISR_0 = 0x100,
        ISR_1 = 0x110,
        ISR_2 = 0x120,
        ISR_3 = 0x130,
        ISR_4 = 0x140,
        ISR_5 = 0x150,
        ISR_6 = 0x160,
        ISR_7 = 0x170,

        TMR_0 = 0x180,
        TMR_1 = 0x190,
        TMR_2 = 0x1A0,
        TMR_3 = 0x1B0,
        TMR_4 = 0x1C0,
        TMR_5 = 0x1D0,
        TMR_6 = 0x1E0,
        TMR_7 = 0x1F0,

        IRR_0 = 0x200,
        IRR_1 = 0x210,
        IRR_2 = 0x220,
        IRR_3 = 0x230,
        IRR_4 = 0x240,
        IRR_5 = 0x250,
        IRR_6 = 0x260,
        IRR_7 = 0x270,

        ESR = 0x280,
        CMCI = 0x2F0,

        ICR_0 = 0x300,
        ICR_1 = 0x310,

        lvt_timer = 0x320,
        lvt_thermal_sensor = 0x330,
        lvt_performance_monitoring_counters = 0x340,
        lvt_LINT0 = 0x350,
        lvt_LINT1 = 0x360,
        lvt_error = 0x370,

        initial_count = 0x380,
        current_count = 0x390,
        divide_config = 0x3E0,
        fn read_register(apic_register: Register) u32 {
            const offset: u16 = @intFromEnum(apic_register);
            return @as(*u32, @ptrFromInt(mem.V_MEM.paddr_2_high_half(ia32_apic_base.getAddress() + offset))).*;
        }

        fn write_register(apic_register: Register, value: u32) void {
            const offset: u16 = @intFromEnum(apic_register);
            var ptr: *volatile u32 = @ptrFromInt(mem.V_MEM.paddr_2_high_half(ia32_apic_base.getAddress() + offset));
            ptr.* = value;
        }
    };
};

fn generate_handle(comptime num: u8) fn () callconv(.Naked) void {
    const error_code_list = [_]u8{ 8, 10, 11, 12, 13, 14, 17, 21, 29, 30 };

    const public = std.fmt.comptimePrint(
        \\     push ${}
        \\     push %rax
        \\     push %rcx
        \\     push %rdx
        \\     push %rbx
        \\     push %rsp
        \\     push %rbp
        \\     push %rsi
        \\     push %rdi
        \\     mov %rsp, context
    , .{num});

    const save_status = if (for (error_code_list) |value| {
        if (value == num) {
            break true;
        }
    } else false)
        public
    else
        \\     push $0b10000000000000000
        \\
        // Note: the Line breaks are very important
            ++
            public;
    const restore_status =
        \\     mov context, %rsp
        \\     pop %rdi
        \\     pop %rsi
        \\     pop %rbp
        \\     pop %rsp
        \\     pop %rbx
        \\     pop %rdx
        \\     pop %rcx
        \\     pop %rax
        \\     add $16, %rsp
        \\     iretq
    ;
    return struct {
        fn handle() callconv(.Naked) void {
            asm volatile (save_status ::: "memory");
            asm volatile ("call interruptDispatch");
            asm volatile (restore_status ::: "memory");
        }
    }.handle;
}
