const std = @import("std");
const gdt = @import("gdt.zig");
const tty = @import("tty.zig");
const mem = @import("mem.zig");
const vmem = @import("vmem.zig");
const cpu = @import("cpu");
const ipc = @import("ipc.zig");
const scheduler = @import("scheduler.zig");
const interrupt = @import("interrupt.zig");
const Process = @import("process.zig").Process;

const Mailbox = ipc.Mailbox;
const x86 = cpu.x86;
const layout = x86.layout;
const Array = std.ArrayList;
const Queue = std.TailQueue;

const STACK_SIZE = x86.constant.PAGE_SIZE; // Size of thread stacks.

// List of threads inside a process.
// TODO
pub const ThreadList = Array(Thread);
// Queue of threads (for scheduler and mailboxes).
pub const ThreadQueue = Queue(Thread);

// Keep track of all the threads.
var threads = Array(?*Thread).init(&mem.allocator);

pub const Thread = struct {
    context: interrupt.Context,
    process: *Process,

    local_tid: u8,
    tid: u16,

    message_destination: *ipc.Message, // Address where to deliver messages.
    mailbox: Mailbox, // Private thread mailbox.

    ////
    // Create a new thread inside the current process.
    // NOTE: Do not call this function directly. Use Process.createThread instead.
    //
    // Arguments:
    //     entry_point: The entry point of the new thread.
    //
    // Returns:
    //     Pointer to the new thread structure.
    //
    pub fn init(process: *Process, local_tid: u8, entry_point: usize) *Thread {
        if (scheduler.current_process == process) {
            tty.panic("current process is not self, id: ", .{});
        }

        // Allocate and initialize the thread structure.
        const thread = mem.allocator.createOne(Thread) catch unreachable;
        thread.* = Thread{
            .context = initContext(entry_point),
            .process = process,
            .local_tid = local_tid,
            .tid = @intCast(u16, threads.len),
            // .process_link = ThreadList.Node.init({}),
            // .queue_link = ThreadQueue.Node.init({}),
            .mailbox = Mailbox{},
            .message_destination = undefined,
        };
        threads.append(@ptrCast(?*Thread, thread)) catch unreachable;
        // TODO: simplify once #836 is solved.

        return thread;
    }

    ////
    // Destroy the thread and schedule a new one if necessary.
    //
    pub fn destroy(self: *Thread) void {
        if (scheduler.current_process != self.process) {
            // TODO, need change
            tty.panic("error", .{});
        }

        // Get the thread off the process and scheduler, and deallocate its structure.
        self.process.removeThread(self);
        threads.items[self.tid] = null;
        mem.allocator.destroy(self);

        // TODO: get the thread off IPC waiting queues.
    }
};

////
// Get a thread.
//
// Arguments:
//     tid: The ID of the thread.
//
// Returns:
//     Pointer to the thread, null if non-existent.
//
pub fn get(tid: u16) ?*Thread {
    return threads.items[tid];
}

////
// Set up the initial context of a thread.
//
// Arguments:
//     entry_point: Entry point of the thread.
//     stack: The beginning of the stack.
//
// Returns:
//     The initialized context.
//
fn initContext(entry_point: usize) interrupt.Context {
    return interrupt.Context{
        .cs = gdt.USER_CODE | gdt.USER_RPL,
        .ss = gdt.USER_DATA | gdt.USER_RPL,
        .eip = entry_point,
        .esp = 0,
        .eflags = 0x202,

        .registers = interrupt.Registers{},
        .interrupt_n = 0,
        .error_code = 0,
    };
}
