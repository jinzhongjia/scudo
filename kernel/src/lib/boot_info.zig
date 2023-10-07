const limine = @import("limine");
const tty = @import("tty.zig");
const time = @import("time.zig");

const Time = time.Time;

pub export var boot_time_request: limine.BootTimeRequest = .{};

fn bootTimeStamp() i64 {
    if (boot_time_request.response) |response| {
        return response.boot_time;
    }
    @panic("sorry, now we get boot time stamp fails");
}

pub fn bootTime2UTC() Time {
    var timeStamp = bootTimeStamp();
    return time.timeStamp2UTC(@intCast(timeStamp));
}
