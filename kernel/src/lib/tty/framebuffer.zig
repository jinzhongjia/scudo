const std = @import("std");
const limine = @import("limine");

export var framebuffer_request: limine.FramebufferRequest = .{};

pub var address: [*]u8 = undefined;

pub var width: u64 = undefined;

pub var height: u64 = undefined;

pub var pixelwidth: u16 = undefined;

pub var pitch: u64 = undefined;

/// 必须要先执行该函数再使用导出的变量！！！
pub fn init() void {
    if (framebuffer_request.response) |response| {
        const framerbuffers = response.framebuffers();

        const framebuffer = framerbuffers[0];

        address = framebuffer.address;

        width = framebuffer.width;

        height = framebuffer.height;

        pixelwidth = framebuffer.bpp / 8;

        pitch = framebuffer.pitch;
    } else {
        unreachable;
    }
}

// frambebuffer的条目，每个像素点的内存结构
pub const Entry = packed struct {
    const This = @This();
    blue: u8 = 0x00,
    green: u8 = 0x00,
    red: u8 = 0x00,
    reserved: u8 = 0x00,
    pub fn make_from_hex(comptime color_code: u64) This {
        const max_color = 0xffffff;
        const min_color = 0x000000;
        if (color_code > max_color or color_code < min_color) {
            @compileError(std.fmt.comptimePrint("color code is error!", .{color_code}));
        }

        return This{
            .blue = @intCast(0x0000ff & color_code),
            .green = @intCast(0x00ff & (color_code >> 8)),
            .red = @intCast(color_code >> 16),
        };
    }
};

// 定义一些基本颜色
pub const color = struct {
    pub const black = Entry{};
    pub const white = Entry{
        .blue = 0xff,
        .green = 0xff,
        .red = 0xff,
    };
    pub const blue = Entry{
        .blue = 0xff,
    };
    pub const green = Entry{
        .green = 0xff,
    };
    pub const red = Entry{
        .red = 0xff,
    };
    pub const yellow = Entry{
        .green = 0xff,
        .red = 0xff,
    };
    pub const cyan_blue = Entry.make_from_hex(0x009ad6);
};
