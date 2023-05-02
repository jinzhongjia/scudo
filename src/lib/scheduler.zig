const timer = @import("timer.zig");
const tty = @import("tty.zig");
const Process = @import("process.zig").Process;
const Thread = @import("thread.zig").Thread;
const ThreadQueue = @import("thread.zig").ThreadQueue;

pub var current_process: *Process = undefined; // The process that is currently executing.
var ready_queue: ThreadQueue = undefined; // Queue of threads ready for execution.

////
// Initialize the scheduler.
//
pub fn initialize() void {
    tty.step("Initializing the Scheduler", .{});

    timer.registerHandler(schedule);
    tty.stepOK();
}

////
// Schedule to the next thread in the queue.
// Called at each timer tick.
//
fn schedule() void {
    // here we will try to schedule task
    // time slice rotation

    gogo();
}

var tmp: usize = 0;

fn gogo() void {
    tty.println("scheduler: {d}", .{tmp});
    // tty.println("ceshi", .{});
    tmp += 1;
}
