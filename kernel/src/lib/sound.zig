const clock = @import("clock.zig");
const cpu = @import("../cpu.zig");
const config = @import("config");

const PIT = clock.PIT;

pub fn init() void {
    if (config.enable_PC_SPEAKER) {
        PC_SPEAKER.init();
    }
}

pub const PC_SPEAKER = struct {
    const BEEP_COUNTER = PIT.OSCILLATOR / 440;

    const SPEAKER_PORT = 0x61;

    fn init() void {

        // config for PIT 2
        cpu.outb(PIT.PIT_CMD, 0b10110110);
        cpu.outb(0x42, @truncate(BEEP_COUNTER));
        cpu.outb(0x42, @truncate(BEEP_COUNTER >> 8));

        {
            PIT.register_handle(speaker_handle);
        }
    }

    pub fn start_beep() void {
        cpu.outb(SPEAKER_PORT, cpu.inb(0x61) | 0b11);
    }

    pub fn stop_beep() void {
        cpu.outb(SPEAKER_PORT, cpu.inb(0x61) & 0xfc);
    }
};

var counter: u8 = 0;
var enable = false;
fn speaker_handle() void {
    if (!enable and counter < 50) {
        PC_SPEAKER.start_beep();
        enable = true;
    }

    if (enable and counter > 50) {
        PC_SPEAKER.stop_beep();
        enable = false;
    }

    counter = (counter + 1) % 100;
}
