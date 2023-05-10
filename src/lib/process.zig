const tty = @import("tty.zig");
const mem = @import("mem.zig");
const vmem = @import("vmem.zig");
const thread = @import("thread.zig");
const scheduler = @import("scheduler.zig");
const elf = @import("elf.zig");

const Thread = thread.Thread;
const ThreadList = thread.ThreadList;

// Keep track of the used PIDs.
var next_pid: u16 = 1;

// Structure representing a process.
pub const Process = struct {
    pid: u16,
    // page_directory: usize,

    next_local_tid: u8,
    threads: ThreadList,

    ////
    // Create a new process and switch to it.
    //
    // Arguments:
    //     elf_addr: Pointer to the beginning of the ELF file.
    //
    // Returns:
    //     Pointer to the new process structure.
    //
    pub fn create(elf_addr: usize, args: ?[]const []const u8) *Process {
        _ = args;
        var process = mem.allocator.create(Process) catch {
            tty.panic("alloc mem to create process failed", .{});
        };
        process.* = Process{
            .pid = next_pid,
            // .page_directory = vmem.createAddressSpace(),
            .next_local_tid = 1,
            .threads = ThreadList.init(mem.allocator),
        };
        next_pid += 1;
        // TODO

        // Switch to the new address space...
        scheduler.switchProcess(process);
        // ...so that we can extract the ELF inside it...
        const entry_point = elf.load(elf_addr);
        // ...and start executing it.
        const main_thread = createThread(entry_point);
        _ = main_thread;
        // insertArguments(main_thread, args orelse [][]const u8{});

        return process;
    }

    ////
    // Destroy the process.
    //
    pub fn destroy(self: *Process) void {
        if (scheduler.current_process != self) {
            tty.panic("destroy process failed", .{});
        }
        // Deallocate all of user space.
        // vmem.destroyAddressSpace();

        {
            var node = self.threads.popOrNull();
            while (node == null) {
                node.?.destroy();
            }
        }
        mem.allocator.destroy(self);
    }

    ////
    // Create a new thread in the process.
    //
    // Arguments:
    //    entry_point: The entry point of the new thread.
    //
    // Returns:
    //    The TID of the new thread.
    //
    pub fn createThread(self: *Process, entry_point: usize) *Thread {
        const thread_tmp = Thread.init(self, self.next_local_tid, entry_point);

        // TODO fix
        self.threads.append(&thread_tmp);
        self.next_local_tid += 1;

        // Add the thread to the scheduling queue.
        scheduler.new(thread_tmp);
        return thread;
    }

    ////
    // Remove a thread from scheduler queue and list of process's threads.
    // NOTE: Do not call this function directly. Use Thread.destroy instead.
    //
    // Arguments:
    //     thread: The thread to be removed.
    //
    fn removeThread(self: *Process, thread_tmp: *Thread) void {
        scheduler.remove(thread_tmp);
        self.threads.remove(&thread_tmp);

        // TODO: handle case in which this was the last thread of the process.
    }
};
