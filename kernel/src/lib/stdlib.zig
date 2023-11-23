const tty = @import("tty.zig");
pub fn bcd_to_integer(bcd_value: u8) u8 {
    return (bcd_value & 0xf) + (bcd_value >> 4) * 10;
}

pub fn integer_to_bcd(value: u8) u8 {
    return (value / 10) * 0x10 + (value % 10);
}

/// bitmaps type
pub const bitmap_t = struct {
    bits: []u8,
    offset: u64,

    pub fn init(addr: usize, size: u64, offset: u64) bitmap_t {
        var bits_ptr: [*]u8 = @ptrFromInt(addr);
        const bits: []u8 = bits_ptr[0..size];
        @memset(bits, 0);
        return bitmap_t{
            .bits = bits,
            .offset = offset,
        };
    }

    pub fn test_bit(bitmap: bitmap_t, index: u64) bool {
        if (index < bitmap.offset) {
            tty.panicf("test_bit is error, index {} is less than bitmap's offset {}", .{ index, bitmap.offset });
        }

        const idx = index - bitmap.offset;

        const bytes = idx / 8;

        if (bytes >= bitmap.bits.len) {
            tty.panicf("test_bit is error, index {} is more than bitmap's length {}", .{ index, bitmap.bits.len });
        }

        const bits: u3 = @intCast(idx % 8);
        return (bitmap.bits[bytes] & (@as(u8, 1) << bits)) != 0;
    }

    pub fn set_bit(bitmap: bitmap_t, index: u64, value: bool) void {
        if (index < bitmap.offset) {
            tty.panicf("set_bit is error, index {} is less than bitmap's offset {}", .{ index, bitmap.offset });
        }

        const idx = index - bitmap.offset;

        const bytes = idx / 8;

        if (bytes >= bitmap.bits.len) {
            tty.panicf("set_bit is error, index {} is more than bitmap's length {}", .{ index, bitmap.bits.len });
        }

        const bits: u3 = @intCast(idx % 8);

        if (value) {
            bitmap.bits[bytes] |= (@as(u8, 1) << bits);
        } else {
            bitmap.bits[bytes] &= ~(@as(u8, 1) << bits);
        }
    }

    pub fn scan(bitmap: bitmap_t, count: u64) ?u64 {
        var is_find = false;
        var start: u64 = 0;
        var bits_left = bitmap.bits.len * 8;
        var next_bit: u64 = 0;
        var counter: u64 = 0;

        if (count > bitmap.bits.len) {
            return null;
        }

        while (bits_left > 0) : (bits_left -= 1) {
            if (!bitmap.test_bit(bitmap.offset + next_bit)) {
                counter += 1;
            } else {
                counter = 0;
            }

            next_bit += 1;
            if (counter == count) {
                start = next_bit - count;
                is_find = true;
                break;
            }
        }

        if (!is_find) {
            return null;
        }

        bits_left = count;
        next_bit = start;

        while (bits_left > 0) : (bits_left -= 1) {
            bitmap.set_bit(bitmap.offset + next_bit, true);
            next_bit += 1;
        }

        return start + bitmap.offset;
    }
};
