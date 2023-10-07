const cpu = @import("../cpu.zig");
const stdlib = @import("stdlib.zig");
const tty = @import("tty.zig");

// !!!!
// We assume that CMOS does not change during system operation

const UTC_BASE_YEAR = 1970;

const MONTH_PER_YEAR = 12;
const DAY_PER_YEAR = 365;
const SEC_PER_DAY = 86400;
const SEC_PER_HOUR = 3600;
const SEC_PER_MIN = 60;

pub fn init() void {
    var register_b = CMOS.cmos_read(CMOS.CMOS_B);
    if (register_b & 0x04 == 0) {
        CMOS.is_BCD = true;
    }
    if (register_b & 0x02 == 0) {
        CMOS.is_24_hour = false;
    }
}

pub const nowTime = CMOS.time_read;

pub const Time = struct {
    second: u8,
    minute: u8,
    hour: u8,
    day: u8,
    month: u8,
    year: u16,
};

/// Acorring to osdev, CMOS can provide time for us
/// https://wiki.osdev.org/CMOS
const CMOS = struct {
    var is_24_hour = true;
    var is_BCD = false;

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

    fn time_read() Time {
        var second: u8 = undefined;
        var minute: u8 = undefined;
        var hour: u8 = undefined;
        var day: u8 = undefined;
        var month: u8 = undefined;
        var year: u16 = undefined;
        var century: u16 = undefined;

        while (is_update()) {}

        {
            second = cmos_read(CMOS_SECOND);
            minute = cmos_read(CMOS_MINUTE);
            hour = cmos_read(CMOS_HOUR);
            day = cmos_read(CMOS_DAY);
            month = cmos_read(CMOS_MONTH);
            year = cmos_read(CMOS_YEAR);
            century = cmos_read(CMOS_CENTURY);

            while (cmos_read(CMOS_SECOND) != second) {
                second = cmos_read(CMOS_SECOND);
                minute = cmos_read(CMOS_MINUTE);
                hour = cmos_read(CMOS_HOUR);
                day = cmos_read(CMOS_DAY);
                month = cmos_read(CMOS_MONTH);
                year = cmos_read(CMOS_YEAR);

                // TODO: read century register
                century = cmos_read(CMOS_CENTURY);
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
            century = stdlib.bcd_to_integer(@intCast(century));
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
            .year = century * 100 + year,
        };
    }
};

pub const TIME_ZONE = enum(i8) { IDLW = -12, CTorCST = 8 };

const days_per_mon = [MONTH_PER_YEAR]u8{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };

fn is_leap_year(year: u16) bool {
    if (year % 400 == 0) {
        return true;
    } else if (year % 100 == 0) {
        return false;
    } else if (year % 4 == 0) {
        return true;
    }
    return false;
}

fn get_days_per_month(month: u8, year: u16) u8 {
    if (month > 12) {
        @panic("month is not correct");
    }
    if (month != 2) {
        return days_per_mon[month - 1];
    }

    if (is_leap_year(year)) {
        return days_per_mon[1] + 1;
    }
    return days_per_mon[1];
}

pub fn timeStamp2UTC(timeStamp: u64) Time {
    var year: u16 = 0;
    var month: u8 = 0;
    var day: u8 = 0;
    var hour: u8 = 0;
    var minute: u8 = 0;
    var second: u8 = 0;

    var days = @divTrunc(timeStamp, SEC_PER_DAY);

    var dayTmp: u32 = 0;

    {
        var yearTmp: u16 = 0;
        yearTmp = UTC_BASE_YEAR;
        while (days > 0) {
            dayTmp = if (is_leap_year(yearTmp)) DAY_PER_YEAR + 1 else DAY_PER_YEAR;
            if (days >= dayTmp) {
                days -= dayTmp;
            } else {
                break;
            }
            yearTmp = yearTmp + 1;
        }
        year = yearTmp;
    }

    {
        var monthTmp: u8 = 1;
        while (monthTmp < MONTH_PER_YEAR) {
            dayTmp = get_days_per_month(monthTmp, year);
            if (days >= dayTmp) {
                days -= dayTmp;
            } else {
                break;
            }
            monthTmp = monthTmp + 1;
        }
        month = monthTmp;
    }

    day = @intCast(days + 1);

    var secs: u32 = @intCast(@mod(timeStamp, SEC_PER_DAY));
    //这个时间戳值的小时数。
    hour = @intCast(secs / SEC_PER_HOUR);
    //这个时间戳值的分钟数。
    secs %= SEC_PER_HOUR;
    minute = @intCast(secs / SEC_PER_MIN);
    //这个时间戳的秒钟数。
    second = @intCast(secs % SEC_PER_MIN);

    return Time{
        .year = year,
        .month = month,
        .day = day,
        .hour = hour,
        .minute = minute,
        .second = second,
    };
}

pub fn UTC2(UTC_time: Time, zone: TIME_ZONE) Time {
    var year: u16 = undefined;
    var month: u8 = undefined;
    var day: u8 = undefined;
    var hour: u8 = @intCast(@as(i8, @intCast(UTC_time.hour)) + @intFromEnum(zone));
    if (@intFromEnum(zone) > 0) {
        day = if (hour > 24) UTC_time.day + 1 else UTC_time.day;
        hour = hour % 24;
        if (day > get_days_per_month(UTC_time.month, UTC_time.year)) {
            day = day % get_days_per_month(UTC_time.month, UTC_time.year);
            month = UTC_time.month + 1;
        } else {
            month = UTC_time.month;
        }

        year = if (month > 12) UTC_time.year + 1 else UTC_time.year;
        month = month % 12;
    } else {
        day = if (hour < 0) UTC_time.day - 1 else UTC_time.day;
        hour = (hour + 24) % 24;
        if (day < 1) {
            day = (day + get_days_per_month(UTC_time.month + 1, UTC_time.year)) % get_days_per_month(UTC_time.month + 1, UTC_time.year);
            month = UTC_time.month - 1;
        } else {
            month = UTC_time.month;
        }

        year = if (month < 1) UTC_time.year - 1 else UTC_time.year;
        month = (month + 12) % 12;
    }
    return Time{
        .year = year,
        .month = month,
        .day = day,
        .hour = hour,
        .minute = UTC_time.minute,
        .second = UTC_time.second,
    };
}
