const std = @import("std");
const tty = @import("tty.zig");
const interrupt = @import("interrupt.zig");
const Process = @import("process.zig").Process;

const Array = std.ArrayList;
const List = std.SinglyLinkedList;

// List of threads inside a process.
pub const ThreadList  = List(void);
// Queue of threads (for scheduler and mailboxes).
pub const ThreadQueue = List(void);

pub const Thread = struct {
    // TODO: simplify once #679 is solved.
    process_link: List(void).Node,
    queue_link: List(void).Node,

    context: interrupt.context,
    process: *Process,

    local_tid: u8,
    tid: u16,
};
