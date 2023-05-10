const std = @import("std");
const x86 = @import("cpu").x86;
const tty = @import("tty.zig");
const mem = @import("mem.zig");
const interrupt = @import("interrupt.zig");

const ArrayList = std.ArrayList;

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

fn gogo() void {

    // Check whether there's data in the keyboard buffer.
    const status = x86.assembly.inb(0x64);
    if ((status & 1) == 0) return;

    // Fetch the scancode, and ignore key releases.
    const code = x86.assembly.inb(0x60);
    if ((code & 0x80) != 0) return;
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
            var char = scancodes[code];
            if (char >= 97 and char <= 122 and ((left_shift or right_shift) or CapsLock)) {
                char -= 32;
            }
            terminal(char);
        },

        0x4A, 0x4E, 0x53 => {
            const char = keypad[code - 0x47];
            terminal(char);
        },
        0x47...0x49, 0x4b...0x4d, 0x4f...0x52 => {
            if (!NumberLock) {
                return;
            }
            const char = keypad[code - 0x47];
            terminal(char);
        },

        else => {},
    }
}

var terminal_buffer: ArrayList(u8) = undefined;
fn terminal(char: u8) void {
    switch (char) {
        '\n' => {
            // @compileLog(@TypeOf(terminal_buffer.items));
            shell(terminal_buffer.items);
            header();
            terminal_buffer.clearAndFree();
        },
        8 => {
            if (terminal_buffer.items.len > 0) {
                _ = terminal_buffer.popOrNull();

                tty.print("{s}", .{[1]u8{char}});
            }
        },
        else => {
            terminal_buffer.append(char) catch unreachable;
            tty.print("{s}", .{[1]u8{char}});
        },
    }
}

const shell_header = "[shell]$ ";

var command_uname = [_]u8{ 'u', 'n', 'a', 'm', 'e' };
var command_echo = [_]u8{ 'e', 'c', 'h', 'o', ' ' };

fn shell(str: []u8) void {
    tty.br();

    if (str.len == 5 and compare(str, &command_uname)) {
        tty.println("System:zos, note: this is a experimental system", .{});
    } else if (str.len >= 5 and compare(str, &command_echo)) {
        tty.println("{s}", .{str[5..str.len]});
    } else {
        tty.println("unknown command", .{});
    }
}

fn compare(str: []u8, other: []u8) bool {
    var i: u8 = 0;
    while (i < other.len) {
        if (str[i] != other[i]) {
            return false;
        }
        i += 1;
    }
    return true;
}

fn header() void {
    tty.ColorPrint(tty.Color.LightGreen, shell_header, .{});
}

pub fn initialize() void {
    terminal_buffer = ArrayList(u8).init(mem.allocator);
    tty.clear();
    header();
    interrupt.registerIRQ(1, gogo);
}
