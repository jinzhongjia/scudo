const timer = @import("timer.zig");
const tty = @import("tty.zig");

////
// Initialize the scheduler.
//
pub fn initialize() void {
    tty.step("Initializing the Scheduler", .{});

    // timer.registerHandler(gogo);
    tty.stepOK();
}

// var tmp: usize = 0;
//
// fn gogo() void {
//     tmp += 1;
//     tty.println("scheduler: {d}", .{tmp});
// }
