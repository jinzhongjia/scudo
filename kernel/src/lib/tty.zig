const std = @import("std");
const builtin = @import("builtin");
const mem = std.mem;
const fmt = std.fmt;
const framebuffer = @import("tty/framebuffer.zig");
const font = @import("tty/font.zig");
const cpu = @import("../cpu.zig");
const config = @import("config.zig");

var maxHeight: u32 = undefined;
var maxWidth: u32 = undefined;

// buffer中的文字的高和宽
var height: u16 = 0;
var width: u16 = 0;

pub fn init() void {
    // 初始化，获取framebuffer信息
    framebuffer.init();
    maxHeight = @intCast(framebuffer.height / font.font_height);
    maxWidth = @intCast(framebuffer.width / font.font_width);
    if (config.if_print_frame_buffer_addr) {
        println("framebuffer addr is 0x{x}", @intFromPtr(framebuffer.address));
    }
}

// 通过当前的文字宽获取x
fn xPos() usize {
    return width * font.font_width * framebuffer.pixelwidth;
}

// 通过当前的高获取y
fn yPos() usize {
    return height * font.font_height * framebuffer.pitch;
}

// 放置一个char进入
fn putchar(FRColor: framebuffer.Entry, BKColor: framebuffer.Entry, char: u8) void {
    const address = framebuffer.address + xPos() + yPos();

    var fontp = font.font_ascii[char];
    for (0..font.font_height) |i| {
        var address_tmp = address + i * framebuffer.pitch;
        var testVal: u32 = 0x100;
        for (0..font.font_width) |_| {
            testVal = testVal >> 1;
            if (fontp[i] & testVal != 0) {
                @as(*framebuffer.Entry, @ptrCast(@alignCast(address_tmp))).* = FRColor;
            } else {
                @as(*framebuffer.Entry, @ptrCast(@alignCast(address_tmp))).* = BKColor;
            }
            address_tmp += framebuffer.pixelwidth;
        }
    }
    updatePos();
}

// 打印字符
fn color_char(FRColor: framebuffer.Entry, BKColor: framebuffer.Entry, char: u8) void {
    switch (char) {
        '\n' => {
            width = 0;
            if (height + 1 >= maxHeight) {
                scrollDown();
                return;
            }
            height += 1;
        },
        '\t' => {
            putchar(FRColor, BKColor, ' ');
            while (width % 4 != 0) {
                putchar(FRColor, BKColor, ' ');
            }
        },
        else => {
            putchar(FRColor, BKColor, char);
        },
    }
}

// 字符串打印
pub fn color_string(FRColor: framebuffer.Entry, BKColor: framebuffer.Entry, string: []const u8) void {
    for (string) |char| {
        color_char(FRColor, BKColor, char);
    }
}

/// 更新位置
fn updatePos() void {
    if (width + 1 == maxWidth) {
        if (height + 1 >= maxHeight) {
            // 实现滚动内容
            scrollDown();
        } else {
            height += 1;
        }
        width = 0;
    } else {
        width += 1;
    }
}

/// 向下滚动
pub fn scrollDown() void {
    const address = framebuffer.address;
    const sum = framebuffer.width * framebuffer.height * framebuffer.pixelwidth;
    const first = font.font_height * framebuffer.width * framebuffer.pixelwidth;
    const last = sum - first;
    mem.copyForwards(u8, address[0..last], address[first..sum]);
    if (height > 0) {
        height -= 1;
    }
}

/// 清屏，该处理方案并不好
/// 后续考虑其他方案实现
/// TODO: this function is abnormal
pub fn clear() void {
    const address = framebuffer.address;
    const num = framebuffer.width * framebuffer.height * framebuffer.pixelwidth;
    @memset(address[0..num], 0x00);
    height = 0;
    width = 0;
}

const KWriter = std.io.Writer(
    void,
    error{},
    struct {
        fn writeFn(_: void, bytes: []const u8) !usize {
            color_string(framebuffer.color.white, framebuffer.color.black, bytes);
            return bytes.len;
        }
    }.writeFn,
);

pub fn print(comptime format: []const u8, args: anytype) void {
    // in this function, we use reflection
    // when args is a tuple, we will just pass it to format
    // when args is others, we will wrap it as tuple
    const writer: KWriter = .{ .context = {} };
    const ArgsType = @TypeOf(args);
    const args_type_info = @typeInfo(ArgsType);
    if (args_type_info == .Struct and args_type_info.Struct.is_tuple) {
        fmt.format(writer, format, args) catch {
            @panic("format err!");
        };
    } else if (args_type_info == .Null) {
        fmt.format(writer, format, .{}) catch {
            @panic("format err!");
        };
    } else {
        fmt.format(writer, format, .{args}) catch {
            @panic("format err!");
        };
    }
}

pub fn println(comptime format: []const u8, args: anytype) void {
    print(format ++ "\n", args);
}

// 这是定义的panic函数，用来覆盖默认的
// 具体见这里：
// https://ziglang.org/documentation/master/std/#A;std:builtin.panic
pub fn panic(msg: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    panicf("\nPanic:{s}\n", .{msg});
}

pub fn panicf(comptime format: []const u8, args: anytype) noreturn {
    @setCold(true);
    make_color_printf(framebuffer.color.red).printf(format, args);
    cpu.stopCPU();
}

/// now, we must return a struct
/// if we return a function with parameters contain anytype, compiler will dumped
/// more info: https://github.com/ziglang/zig/issues/17636
fn make_color_printf(comptime FRColor: framebuffer.Entry) type {
    const Writer = std.io.Writer(
        void,
        error{},
        struct {
            fn writeFn(_: void, bytes: []const u8) !usize {
                color_string(FRColor, framebuffer.color.black, bytes);
                return bytes.len;
            }
        }.writeFn,
    );
    return struct {
        fn printf(comptime format: []const u8, args: anytype) void {
            const writer: Writer = .{ .context = {} };

            const ArgsType = @TypeOf(args);
            const args_type_info = @typeInfo(ArgsType);

            if (args_type_info == .Struct and args_type_info.Struct.is_tuple) {
                fmt.format(writer, format, args) catch {};
            } else if (args_type_info == .Null) {
                fmt.format(writer, format, .{}) catch {};
            } else {
                fmt.format(writer, format, .{args}) catch {};
            }
        }
    };
}

pub fn logf(comptime format: []const u8, args: anytype) void {
    @setCold(true);
    make_color_printf(framebuffer.color.yellow).printf(format, args);
}

/// for log implemention
pub const std_options = struct {
    pub const log_level = std.log.Level.debug;
    pub fn logFn(comptime level: std.log.Level, comptime scope: @TypeOf(.EnumLiteral), comptime format: []const u8, args: anytype) void {
        const scope_prefix = "(" ++ switch (builtin.mode) {
            .Debug => @tagName(scope),
            else => if (@intFromEnum(level) <= @intFromEnum(std.log.Level.info))
                @tagName(scope)
            else
                return,
        } ++ "): ";

        const prefix = "[" ++ comptime level.asText() ++ "] " ++ scope_prefix;
        logf(prefix ++ format ++ "\n", args);
    }
};
