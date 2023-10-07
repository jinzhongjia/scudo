const cpu = @import("../cpu.zig");
const stdlib = @import("stdlib.zig");

// !!!!
// We assume that CMOS does not change during system operation

var is_24_hour = true;
var is_BCD = false;

pub fn init() void {
    var register_b = cmos_read(CMOS_B);
    if (register_b & 0x04 == 0) {
        is_BCD = true;
    }
    if (register_b & 0x02 == 0) {
        is_24_hour = false;
    }
}

pub const Time = struct {
    second: u8,
    minute: u8,
    hour: u8,
    day: u8,
    month: u8,
    year: u16,
};

const CMOS_ADDR = 0x70;
const CMOS_DATA = 0x71;

// for disable NMI
const CMOS_NMI = 0x80;

const CMOS_SECOND = 0x00;
const CMOS_MINUTE = 0x02;
const CMOS_HOUR = 0x04;
const CMOS_WEEKDAY = 0x06; // Accorrding to osdev,weekday register is unreliable, we should not use it.
const CMOS_DAY = 0x07;
const CMOS_MONTH = 0x08;
const CMOS_YEAR = 0x09;
const CMOS_CENTURY = 0x32;

const CMOS_A = 0x0a;
const CMOS_B = 0x0b;
const CMOS_C = 0x0c;
const CMOS_D = 0x0d;

// for read information:
// https://wiki.osdev.org/CMOS#Accessing_CMOS_Registers
fn cmos_read(addr: u8) u8 {
    cpu.outb(CMOS_ADDR, CMOS_NMI | addr);
    return cpu.inb(CMOS_DATA);
}

// Query the A register to obtain whether the current CMOS is updating the time
fn is_update() bool {
    cpu.outb(CMOS_ADDR, CMOS_A);
    return (cpu.inb(CMOS_DATA) >> 7 == 1);
}

pub fn time_read() Time {
    var second: u8 = undefined;
    var minute: u8 = undefined;
    var hour: u8 = undefined;
    var day: u8 = undefined;
    var month: u8 = undefined;
    var year: u16 = undefined;

    while (is_update()) {}

    {
        second = cmos_read(CMOS_SECOND);
        minute = cmos_read(CMOS_MINUTE);
        hour = cmos_read(CMOS_HOUR);
        day = cmos_read(CMOS_DAY);
        month = cmos_read(CMOS_MONTH);
        year = cmos_read(CMOS_YEAR);

        while (cmos_read(CMOS_SECOND) != second) {
            second = cmos_read(CMOS_SECOND);
            minute = cmos_read(CMOS_MINUTE);
            hour = cmos_read(CMOS_HOUR);
            day = cmos_read(CMOS_DAY);
            month = cmos_read(CMOS_MONTH);
            year = cmos_read(CMOS_YEAR);
            // TODO: read century register
        }
    }

    if (is_BCD) {
        // convert BCD to interger
        second = stdlib.bcd_to_integer(second);
        minute = stdlib.bcd_to_integer(minute);
        hour = stdlib.bcd_to_integer(hour);
        day = stdlib.bcd_to_integer(day);
        month = stdlib.bcd_to_integer(month);
        year = stdlib.bcd_to_integer(@intCast(year));
    }

    if (!is_24_hour) {
        hour = ((hour & 0x7F) + 12) % 24;
    }

    return Time{
        .second = second,
        .minute = minute,
        .hour = hour,
        .day = day,
        .month = month,
        .year = year,
    };
}
