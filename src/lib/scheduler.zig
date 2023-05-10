const cpu = @import("cpu");
const gdt = @import("gdt.zig");
const interrupt = @import("interrupt.zig");
const timer = @import("timer.zig");
const tty = @import("tty.zig");
const mem = @import("mem.zig");
const x86 = cpu.x86;
const Process = @import("process.zig").Process;
const Thread = @import("thread.zig").Thread;
const ThreadQueue = @import("thread.zig").ThreadQueue;

pub var current_process: *Process = undefined; // The process that is currently executing.
pub var current_thread: *Thread = undefined;
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

    if (ready_queue.popFirst()) |next| {
        ready_queue.append(next);
        contextSwitch(&next.data);
    }
}

////
// Set up a context switch to a thread.
//
// Arguments:
//     thread: The thread to switch to.
//
fn contextSwitch(thread: *Thread) void {
    switchProcess(thread.process);

    interrupt.context = &thread.context;
    // TODO: why?
    // gdt.setKernelStack(@ptrToInt(interrupt.context) + @sizeOf(interrupt.Context));
}

////
// Switch to the address space of a process, if necessary.
//
// Arguments:
//     process: The process to switch to.
//
pub fn switchProcess(process: *Process) void {
    if (current_process != process) {
        // x86.assembly.writeCR3(process.page_directory);
        current_process = process;
    }
}

////
// Add a new thread to the scheduling queue.
// Schedule it immediately.
//
// Arguments:
//     new_thread: The thread to be added.
//
pub fn new(new_thread: *Thread) void {
    var node = mem.allocator.create(ThreadQueue.Node) catch {
        tty.panic("create ready_queue node failed", .{});
    };
    node.data = new_thread.*;
    ready_queue.append(node);
    contextSwitch(new_thread);
}

////
// Enqueue a thread into the scheduling queue.
// Schedule it last.
//
// Arguments:
//     thread: The thread to be enqueued.
//
pub fn enqueue(thread: *Thread) void {
    // Last element in the queue is the thread currently being executed.
    // So put this thread in the second to last position.
    if (ready_queue.last) |last| {
        ready_queue.insertBefore(last, &thread);
    } else {
        // If the queue is empty, simply insert the thread.
        ready_queue.prepend(&thread);
    }
}

////
// Deschedule the current thread and schedule a new one.
//
// Returns:
//     The descheduled thread.
//
pub fn dequeue() ?*Thread {
    const thread = ready_queue.pop() orelse return null;
    schedule();
    return thread.data;
}

////
// Remove a thread from the scheduling queue.
//
// Arguments:
//     thread: The thread to be removed.
//
pub fn remove(thread: *Thread) void {
    if (thread == current().?) {
        _ = dequeue();
    } else {
        ready_queue.remove(&thread);
    }
}

////
// Return the thread currently being executed.
//
pub inline fn current() ?*Thread {
    const last = ready_queue.last orelse return null;
    return &last.data;
}
