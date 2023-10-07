const limine = @import("limine");
const tty = @import("tty.zig");
const time = @import("time.zig");

const Time = time.Time;

pub export var boot_time_request: limine.BootTimeRequest = .{};

pub fn bootTimeStamp() i64 {
    if (boot_time_request.response) |response| {
        return response.boot_time;
    }
    @panic("sorry, now we get boot time stamp fails");
}

const UTC_BASE_YEAR = 1970;

const MONTH_PER_YEAR = 12;
const DAY_PER_YEAR = 365;
const SEC_PER_DAY = 86400;
const SEC_PER_HOUR = 3600;
const SEC_PER_MIN = 60;

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

pub fn bootTime2UTC() Time {
    var timeStamp = bootTimeStamp();
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

    day = @intCast(@as(i64, @truncate(days + 1)));

    var secs: u32 = @intCast(@as(i64, @mod(timeStamp, SEC_PER_DAY)));
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

pub const time_zone = enum(i8) { IDLW = -12, CTorCST = 8 };

pub fn bootTimeUTC2(zone: time_zone) Time {
    var UTC_time = bootTime2UTC();
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
