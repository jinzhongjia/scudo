const lib = @import("lib.zig");
const cpu = @import("cpu.zig");

const scancodes = [_]u8{
    0,    27,  '1', '2', '3', '4', '5', '6', '7', '8', '9',  '0', '-', '=',  8,
    '\t', 'q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p',  '[', ']', '\n', 0,
    'a',  's', 'd', 'f', 'g', 'h', 'j', 'k', 'l', ';', '\'', '`', 0,   '\\', 'z',
    'x',  'c', 'v', 'b', 'n', 'm', ',', '.', '/', 0,   '*',  0,   ' ', 0,    0,
    0,    0,   0,   0,   0,   0,   0,   0,   0,   0,   0,    0,   0,   0,    '-',
    0,    0,   0,   '+', 0,   0,   0,   0,   0,   0,   0,    0,   0,   0,    0,
};

const keypad = [_]u8{ '7', '8', '9', '-', '4', '5', '6', '+', '1', '2', '3', '0', '.' };

// when true is input 'A'
var CapsLock: bool = false;
// when true is input number
var NumberLock: bool = false;

var left_shift: bool = false;
var right_shift: bool = false;

fn handle_keyboard() void {
    // Check whether there's data in the keyboard buffer.
    const status = cpu.inb(0x64);
    if ((status & 1) == 0) return;

    // Fetch the scancode, and ignore key releases.
    const code = cpu.inb(0x60);
    // if ((code & 0x80) != 0) return;

    handle(code);
}

fn handle(code: u16) void {
    switch (code) {
        0x3a => {
            CapsLock = !CapsLock;
        },
        // NumberLock
        0x45 => {
            NumberLock = !NumberLock;
        },
        // left shift
        0x2a, 0xaa => {
            left_shift = !left_shift;
        },
        // right shift
        0x36, 0xb6 => {
            right_shift = !right_shift;
        },

        0x00...0x29, 0x2b...0x35, 0x37...0x39, 0x3b...0x44 => {
            // Fetch the character associated with the keypress.
            if (code == 0x0e) {
                lib.tty.back_char();
                return;
            }
            var char = scancodes[code];
            if (char >= 97 and char <= 122 and ((left_shift or right_shift) or CapsLock)) {
                char -= 32;
            }
            lib.tty.print("{c}", char);
        },

        0x4A, 0x4E, 0x53 => {
            const char = keypad[code - 0x47];
            lib.tty.print("{c}", char);
        },
        0x47...0x49, 0x4b...0x4d, 0x4f...0x52 => {
            if (!NumberLock) {
                return;
            }
            const char = keypad[code - 0x47];
            lib.tty.print("{c}", char);
        },

        else => {},
    }
}

pub fn init() void {
    lib.idt.registerInterruptHandle(0x20 + 1, handle_keyboard);
}
