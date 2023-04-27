const fmt = @import("std").fmt;
const VGA = @import("vga.zig");

const x86 = @import("cpu").x86;

var vga_instance = VGA.VGA{};

////
// Initialize the terminal.
//
pub fn initialize() void {
    VGA.disableCursor();
    vga_instance.clear();

    var tmp: u8 = 8;
    print("number:{d}", .{tmp}); // will errors
    print("number:{d}", .{8}); // will run ok
}

const KWriter = struct {
    pub const Error = error{};

    const Self = @This();

    pub fn writeAll(_: Self, string: []const u8) Error!void {
        vga_instance.writeString(string);
    }

    pub fn writeByteNTimes(_: Self, byte: u8, n: usize) Error!void {
        var times: usize = n;
        while (times > 0) {
            vga_instance.writeChar(byte);
            times = times - 1;
        }
    }
};

pub fn print(comptime format: []const u8, args: anytype) void {
    const writer: KWriter = .{};
    fmt.format(writer, format, args) catch panic("failed to print, something is wrong", .{});
}

////
// Print a string in the given foreground tty.Color.
//
// Arguments:
//     fg: tty.Color of the text.
//     format: Format string.
//     args: Parameters for format specifiers.
//
pub fn ColorPrint(fg: VGA.Color, comptime format: []const u8, args: anytype) void {
    const save_foreground = vga_instance.foreground;

    vga_instance.foreground = fg;
    print(format, args);

    vga_instance.foreground = save_foreground;
}

pub fn panic(comptime format: []const u8, args: anytype) void {
    // We may be interrupting user mode, so we disable the hardware cursor
    // and fetch its current position, and start writing from there.
    VGA.disableCursor();
    vga_instance.fetchCursor();
    vga_instance.writeChar('\n');

    vga_instance.background = VGA.Color.Red;
    ColorPrint(VGA.Color.White, "KERNEL PANIC: " ++ format ++ "\n", args);

    x86.assembly.hang();
}

////
// Print the statement in the center of this line
//
// Arguments:
//    fg: tty.Color of the text.
//    statement: string printed
//
pub fn ColorCenterPrint(fg: VGA.Color, comptime statement: []const u8) void {
    alignCenter(statement.len);
    ColorPrint(fg, statement, .{});
}

////
// Align the cursor so that it is offset characters from the left border.
//
// Arguments:
//     offset: Number of characters from the left border.
//
pub fn alignLeft(offset: usize) void {
    while (vga_instance.cursor % vga_instance.VGA_WIDTH != offset) {
        vga_instance.writeChar(' ');
    }
}

////
// Align the cursor so that it is offset characters from the right border.
//
// Arguments:
//     offset: Number of characters from the right border.
//
pub fn alignRight(offset: usize) void {
    alignLeft(VGA.VGA_WIDTH - offset);
}

////
// Align the cursor to horizontally center a string.
//
// Arguments:
//     str_len: Length of the string to be centered.
//
pub fn alignCenter(str_len: usize) void {
    alignLeft((VGA.VGA_WIDTH - str_len) / 2);
}

////
// Print a loading step.
//
// Arguments:
//     format: Format string.
//     args: Parameters for format specifiers.
//
pub fn step(comptime format: []const u8, args: anytype) void {
    ColorPrint(VGA.Color.LightBlue, ">> ", .{});
    print(format ++ "...", args);
}

////
// Signal that a loading step completed successfully.
//
pub fn stepOK() void {
    const ok = " [ OK ]";

    alignRight(ok.len);
    ColorPrint(VGA.Color.LightGreen, ok, .{});
}
