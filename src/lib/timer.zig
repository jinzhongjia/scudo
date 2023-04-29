const cpu = @import("cpu");
const tty = @import("tty.zig");
const interrupt = @import("interrupt.zig");

const x86 = cpu.x86;

// Programmable Interval Timer ports.
const PIT_CMD = 0x43;
const PIT_CH_0 = 0x40;
// PIT parameters.
const SQUARE_WAVE_GEN = (0b011 << 1);
const LSB_THEN_MSB = (0b11 << 4);
// Operating frequency of the PIT.
const PIT_FREQUENCY = 1193182;

////
// Initialize the system timer.
//
// Arguments:
//     hz: Frequency of the timer.
//
pub fn initialize(hz: u32) void {
    tty.step("Configuring the System Timer", .{});
    tty.ColorPrint(tty.Color.White, " {d} Hz", .{hz});

    // Calculate the divisor for the required frequency.
    const divisor = PIT_FREQUENCY / hz;

    // Setup the timer to work in Mode 3 (Square Wave Generator).
    x86.assembly.outb(PIT_CMD, SQUARE_WAVE_GEN | LSB_THEN_MSB);

    // Set the desired frequency divisor.
    x86.assembly.outb(PIT_CH_0, @truncate(u8, divisor));
    x86.assembly.outb(PIT_CH_0, @truncate(u8, divisor >> 8));

    tty.stepOK();
}

////
// Register an handler for the timer.
//
pub fn registerHandler(handler: fn () void) void {
    interrupt.registerIRQ(0, handler);
}
