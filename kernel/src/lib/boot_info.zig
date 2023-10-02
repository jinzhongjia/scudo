const limine = @import("limine");

pub export var boot_time_request: limine.BootTimeRequest = .{};

pub fn bootTimeStamp() i64 {
    if (boot_time_request.response) |response| {
        return response.boot_time;
    }
    @panic("sorry, now we get boot time stamp fails");
}

const LEAPOCH = 946684800 + 86400 * (31 + 29);

// days per 400 years
const DAYS_PER_400Y = 365 * 400 + 97;

// days per 100 years
const DAYS_PER_100Y = 365 * 100 + 24;

// days per 4 years
const DAYS_PER_4Y = 365 * 4 + 1;

const Time = struct {
    //seconds
    secs: i64,
    // days of week
    wday: u8,
    // days of month
    mday: u8,
    // days of year
    yday: u16,
};

pub fn bootTime2UTC(timeStamp: i64) Time {
    _ = timeStamp;


}
