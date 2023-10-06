const cpu = @import("../cpu.zig");
const config = @import("./config.zig");
const idt = @import("idt.zig");

const PIC = idt.PIC;

pub fn init() void {
    PIT.init();
}

pub const PIT = struct {
    pub const PIT_CMD = 0x43;
    const PIT_CH_0 = 0x40;

    // for mode 3
    const SQUARE_WAVE_GEN = (0b011 << 1);
    const LOBYTE_THEN_HIBYTE = (0b11 << 4);

    // The oscillator used by the PIT chip runs at (roughly) 1.193182 MHz.
    pub const OSCILLATOR = 1193182;

    const CLOCK_COUNTER = OSCILLATOR / config.PIT_FREQUENCY;

    fn init() void {

        // config for PIT 0
        // Setup the timer to work in Mode 3 (Square Wave Generator).
        cpu.outb(PIT_CMD, SQUARE_WAVE_GEN | LOBYTE_THEN_HIBYTE);

        // write low byte
        cpu.outb(PIT_CH_0, @truncate(CLOCK_COUNTER));
        // write high byte
        cpu.outb(PIT_CH_0, @truncate(CLOCK_COUNTER >> 8));
    }

    pub fn register_handle(handle: *const fn () void) void {
        PIC.registerIRQ(PIC.IRQ.CLOCK, handle);
    }
};
