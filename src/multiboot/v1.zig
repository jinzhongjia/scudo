const MAGIC: u32 = 0x1BADB002;
const ALIGN: u32 = 1 << 0;
const MEMINFO: u32 = 1 << 1;

// Must contain the magic value ‘0x2BADB002’;
// the presence of this value indicates to the operating system that it was loaded
// by a Multiboot-compliant boot loader (e.g. as opposed to another type of boot loader
// that the operating system can also be loaded from).
pub const BOOT_MAGIC = 0x2BADB002;

pub const Header = extern struct {
    magic: u32 = 0x1BADB002, // Must be equal to header magic number.
    flags: u32 = ALIGN | MEMINFO, // Feature flags.
    checksum: u32 = ~(MAGIC +% (ALIGN | MEMINFO)) +% 1, // Above fields plus this one must equal 0 mod 2^32.
};

pub const Info = packed struct {

    // Multiboot info version number
    flags: u32,

    // Available memory from BIOS
    mem_lower: u32,
    mem_upper: u32,

    // "root" partition
    boot_device: u32,

    // Kernel command line
    cmdline: u32,

    // Boot-Module list
    mods_count: u32,
    mods_addr: u32,

    // more we need to read the multiboot v1 specification
    syms: u128,

    // Memory Mapping buffer
    mmap_length: u32,
    mmap_addr: u32,

    // Drive Info buffer
    drives_length: u32,
    drives_addr: u32,

    // ROM configuration table
    config_addr: u32,

    // Boot Loader Name
    boot_loader_name: u32,

    // APM table
    apm_table: u32,

    // video
    vbe_control_info: u32,
    vbe_mode_info: u32,
    vbe_mode: u16,
    vbe_interface_seg: u16,
    vbe_interface_off: u16,
    vbe_interface_len: u16,

    // framebuffer
    framebuffer_addr: u64,
    framebuffer_pitch: u32,
    framebuffer_width: u32,
    framebuffer_height: u32,
    framebuffer_bpp: u8,
    framebuffer_type: u8,

    // color info
    color_info_low: u32,
    color_info_upper: u32,

    const Self = @This();

    ////
    // Return the ending address of the last module.
    //
    pub fn lastModuleEnd(self: *const Self) usize {
        if (self.mods_count == 0)
            return self.mods_addr;
        const mods = @intToPtr([*]module, self.mods_addr);
        return mods[self.mods_count - 1].mod_end;
    }

    ////
    // Load all the modules passed by the bootloader.
    //
    pub fn loadModules(self: *const Self) void {
        _ = self;
        //TODO
    }
};

// Entries in the memory map.
pub const MMap_entry = packed struct {
    size: u32,
    addr: u64,
    len: u64,
    type: u32,
};

pub const module = packed struct {
    // The memory used goes from bytes 'mod_start' to 'mod_end-1' inclusive.
    mod_start: u32,
    mod_end: u32,

    cmdline: u32, // Module command line.
    pad: u32, // Padding to take it to 16 bytes (must be zero).
};

// check flags
pub fn check_flag(flags: u32, bit: u8) bool {
    return (flags) & (1 << (bit));
}
