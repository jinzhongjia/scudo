// stack size in bytes
// now, we applied for 4kB stack
pub const stack_size: u64 = 8 * 1024 * 8;

pub const PIT_FREQUENCY = 100;

/// this will control whether init the PC_SPEAKER
pub const enable_PC_SPEAKER: bool = true;

pub const mem = struct {
    pub const is_print_mem_info: bool = true;

    /// display type: 0 is B, 1 is KB, 2 is MB, 3 is GB
    pub const display_type: u8 = 2;

    pub const if_print_HHDM: bool = false;

    comptime {
        if (display_type > 3) {
            @panic("display_type must be less than 4");
        }
    }
};
