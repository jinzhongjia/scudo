const std = @import("std");
const tty = @import("tty.zig");
const interrupt = @import("interrupt.zig");
const Process = @import("process.zig").Process;

const Array = std.ArrayList;
const Queue = std.TailQueue;

// List of threads inside a process.
pub const ThreadList = Queue(void);
// Queue of threads (for scheduler and mailboxes).
pub const ThreadQueue = Queue(void);

pub const Thread = struct {
    // TODO: simplify once #679 is solved.
    process_link: Queue(void).Node,
    queue_link: Queue(void).Node,

    context: interrupt.Context,
    process: *Process,

    local_tid: u8,
    tid: u16,

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
    fn init(process: *Process, local_tid: u8, entry_point: usize) *Thread {
        if (scheduler.current_process == process) {
            tty.panic("current process is not self, id: ", .{});
        }

        // Calculate the address of the thread stack and map it.
        const stack = getStack(local_tid);
        vmem.mapZone(stack, null, STACK_SIZE, vmem.PAGE_WRITE | vmem.PAGE_USER);

        // Allocate and initialize the thread structure.
        const thread = mem.allocator.createOne(Thread) catch unreachable;
        thread.* = Thread{
            .context = initContext(entry_point, stack),
            .process = process,
            .local_tid = local_tid,
            .tid = @intCast(u16, threads.len),
            .process_link = ThreadList.Node.init({}),
            .queue_link = ThreadQueue.Node.init({}),
            .mailbox = Mailbox.init(),
            .message_destination = undefined,
        };
        threads.append(@ptrCast(?*Thread, thread)) catch unreachable;
        // TODO: simplify once #836 is solved.

        return thread;
    }
};
