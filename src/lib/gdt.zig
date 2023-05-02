const x86 = @import("cpu").x86;
const tty = @import("tty.zig");

// GDT segment selectors.
pub const KERNEL_CODE = 0x08;
pub const KERNEL_DATA = 0x10;
pub const USER_CODE = 0x18;
pub const USER_DATA = 0x20;
pub const TSS_DESC = 0x28;

// Privilege level of segment selector.
pub const KERNEL_RPL = 0b00;
pub const USER_RPL = 0b11;

// Access byte values.
pub const KERNEL = 0x90;
pub const USER = 0xF0;
pub const CODE = 0x0A;
pub const DATA = 0x02;
pub const TSS_ACCESS = 0x89;

// Segment flags.
pub const BLOCKS_4K = (1 << 3);
pub const PROTECTED = (1 << 2); // 32-bit or 16-bit

// Structure representing an entry in the GDT.
// Here we should know packed struct
const Entry = packed struct {
    limit_low: u16,
    base_low: u16,
    base_mid: u8,
    access: u8,
    limit_high: u4,
    flags: u4,
    base_high: u8,
};

// GDT descriptor register.
// GDT register store the pointer of gdt
const Register = packed struct {
    limit: u16,
    base: usize,
};

// Task State Segment.
const TSS = packed struct {
    link: u16 = 0,
    link_reserved: u16 = 0,
    esp0: u32 = 0, // Stack to use when coming to ring 0 from ring > 0.
    ss0: u16 = 0, // Segment to use when coming to ring 0 from ring > 0.
    ss0_reserved: u16 = 0,
    esp1: u32 = 0,
    ss1: u16 = 0,
    ss1_reserved: u16 = 0,
    esp2: u32 = 0,
    ss2: u16 = 0,
    ss2_reserved: u16 = 0,
    cr3: u32 = 0,
    eip: u32 = 0,
    eflags: u32 = 0,
    eax: u32 = 0,
    ecx: u32 = 0,
    edx: u32 = 0,
    ebx: u32 = 0,
    esp: u32 = 0,
    ebp: u32 = 0,
    esi: u32 = 0,
    edi: u32 = 0,
    es: u16 = 0,
    es_reserved: u16 = 0,
    cs: u16 = 0,
    cs_reserved: u16 = 0,
    ss: u16 = 0,
    ss_reserved: u16 = 0,
    ds: u16 = 0,
    ds_reserved: u16 = 0,
    fs: u16 = 0,
    fs_reserved: u16 = 0,
    gs: u16 = 0,
    gs_reserved: u16 = 0,
    ldtr: u16 = 0,
    ldtr_reserved: u16 = 0,
    iopb_reserved: u16 = 0,
    iopb: u16 = 0,
    // why this ?
    // SSP is introduced by intel at the hardware level to enhance security,
    // not all platforms support it
    // ssp: u32 = 0,
};

////
// Generate a GDT entry structure.
//
// Arguments:
//     base: Beginning of the segment.
//     limit: Size of the segment.
//     access: Access byte.
//     flags: Segment flags.
//
fn makeEntry(base: usize, limit: usize, access: u8, flags: u4) Entry {
    return Entry{
        .limit_low = @truncate(u16, limit),
        .base_low = @truncate(u16, base),
        .base_mid = @truncate(u8, base >> 16),
        .access = @truncate(u8, access),
        .limit_high = @truncate(u4, limit >> 16),
        .flags = @truncate(u4, flags),
        .base_high = @truncate(u8, base >> 24),
    };
}

// Fill in the GDT.
var gdt align(4) = [_]Entry{
    makeEntry(0, 0, 0, 0),
    makeEntry(0, 0xFFFFF, KERNEL | CODE, PROTECTED | BLOCKS_4K),
    makeEntry(0, 0xFFFFF, KERNEL | DATA, PROTECTED | BLOCKS_4K),
    makeEntry(0, 0xFFFFF, USER | CODE, PROTECTED | BLOCKS_4K),
    makeEntry(0, 0xFFFFF, USER | DATA, PROTECTED | BLOCKS_4K),
    makeEntry(0, 0, 0, 0), // TSS (fill in at runtime).
};

// GDT descriptor register pointing at the GDT.
var gdtr: Register = Register{
    .limit = @sizeOf(@TypeOf(gdt)) - 1,
    // because the maximum value of Size is 65535, while the GDT can be up to 65536 bytes in length (8192 entries). Further, no GDT can have a size of 0 bytes.
    // base must be assigned  at runtime
    .base = undefined,
};

// Instance of the Task State Segment.
var tss = TSS{
    .esp0 = undefined,
    .ss0 = KERNEL_DATA,
    .iopb = @sizeOf(TSS),
};

////
// Set the kernel stack to use when interrupting user mode.
//
// Arguments:
//     esp0: Stack for Ring 0.
//
fn setKernelStack(esp0: usize) void {
    tss.esp0 = esp0;
}

////
// Initialize the Global Descriptor Table.
//
pub fn initialize() void {
    tty.step("Setting up the Global Descriptor Table", .{});
    gdtr.base = @ptrToInt(&gdt[0]);

    // Initialize GDT.
    loadGDT(&gdtr);

    // Initialize TSS.
    const tss_entry = makeEntry(@ptrToInt(&tss), @sizeOf(TSS) - 1, TSS_ACCESS, 0);
    gdt[TSS_DESC / @sizeOf(Entry)] = tss_entry;
    x86.assembly.ltr(TSS_DESC);

    tty.stepOK();
}

////
// Load the GDT into the system registers (defined in assembly).
//
// Arguments:
//     gdtr: Pointer to the GDTR.
//
extern fn loadGDT(gdtr: *const Register) void;

////
// Load the GDT into the system registers.
//
// Arguments:
//     gdtr: Pointer to the GDTR.
//
comptime {
    asm (
        \\ .type loadGDT, @function
        \\ loadGDT:
        \\     mov +4(%esp), %eax  // Fetch the gdtr parameter.
        \\     lgdt (%eax)         // Load the new GDT.

        // Reload data segments (GDT entry 2: kernel data).
        \\     mov $0x10, %ax
        \\     mov %ax, %ds
        \\     mov %ax, %es
        \\     mov %ax, %fs
        \\     mov %ax, %gs
        \\     mov %ax, %ss

        // Reload code segment (GDT entry 1: kernel code).
        \\     ljmp $0x08, $1f
        \\ 1:  ret
    );
}
