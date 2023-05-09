const tty = @import("tty.zig");
const std = @import("std");
const mem = @import("mem.zig");
const thread = @import("thread.zig");
const scheduler = @import("scheduler.zig");

const Queue = std.TailQueue;
const HashMap = std.HashMap;
const ThreadQueue = thread.ThreadQueue;

//////////////////////////
////  IPC structures  ////
//////////////////////////

pub const Message = struct {
    sender: MailboxId,
    receiver: MailboxId,
    code: usize,
    args: [5]usize,
    // payload: ?[]const u8,

    pub fn from(mailbox_id: MailboxId) Message {
        return Message{
            .sender = MailboxId.Undefined,
            .receiver = mailbox_id,
            .code = undefined,
            .args = undefined,
        };
    }

    pub fn to(mailbox_id: MailboxId, msg_code: usize, args: anytype) Message {
        var message = Message{
            .sender = MailboxId.This,
            .receiver = mailbox_id,
            .code = msg_code,
            .args = undefined,
        };

        const ArgsType = @TypeOf(args);
        const args_type_info = @typeInfo(ArgsType);
        const fields_info = args_type_info.Struct.fields;

        if (fields_info.len > message.args.len) {
            tty.panic("error, args length too many", .{});
        }

        comptime var i = 0;
        inline while (i < fields_info.len) : (i += 1) {
            @field(args, fields_info[i].name);
        }

        return message;
    }

    pub fn as(self: Message, sender: MailboxId) Message {
        var message = self;
        message.sender = sender;
        return message;
    }
};

pub const MailboxId = union(enum) {
    Undefined,
    This,
    Kernel,
    Port: u16,
    Thread: u16,
};

// Structure representing a mailbox.
pub const Mailbox = struct {
    messages: Queue(Message) = .{},
    waiting_queue: ThreadQueue = .{},
    // TODO: simplify once #679 is resolved.

};

// Keep track of the registered ports.
var ports = HashMap(u16, *Mailbox, hash_u16, eql_u16).init(&mem.allocator);

fn hash_u16(x: u16) u32 {
    return x;
}
fn eql_u16(a: u16, b: u16) bool {
    return a == b;
}

////
// Get the port with the given ID, or create one if it doesn't exist.
//
// Arguments:
//     id: The index of the port.
//
// Returns:
//     Mailbox associated to the port.
//
pub fn getOrCreatePort(id: u16) *Mailbox {
    // TODO: check that the ID is not reserved.
    if (ports.get(id)) |entry| {
        return entry.value;
    }

    const mailbox = mem.allocator.create(Mailbox) catch {
        tty.panic("Create mailbox failed", .{});
    };
    mailbox.* = Mailbox{};

    _ = ports.put(id, mailbox) catch {
        tty.panic("put hashmap failed", .{});
    };
    return mailbox;
}

////
// Get the mailbox associated with the given mailbox ID.
//
// Arguments:
//     mailbox_id: The ID of the mailbox.
//
// Returns:
//     The address of the mailbox.
//
fn getMailbox(mailbox_id: MailboxId) *Mailbox {
    return switch (mailbox_id) {
        MailboxId.This => &(scheduler.current().?).mailbox,
        MailboxId.Thread => |tid| &(thread.get(tid).?).mailbox,
        MailboxId.Port => |id| getOrCreatePort(id),
        else => unreachable,
    };
}

////
// Process the outgoing message. Return a copy of the message with
// an explicit sender field and the physical address of a copy of
// the message's payload (if specified).
//
// Arguments:
//     message: The original message.
//
// Returns:
//     A copy of the message, post processing.
//
fn processOutgoingMessage(message: Message) Message {
    var message_copy = message;

    switch (message.sender) {
        MailboxId.This => message_copy.sender = MailboxId{ .Thread = scheduler.current().?.tid },
        // MailboxId.Port   => TODO: ensure the sender owns the port.
        // MailboxId.Kernel => TODO: ensure the sender is really the kernel.
        else => {},
    }

    return message_copy;
}

////
// Deliver a message to the current thread.
//
// Arguments:
//     message: The message to be delivered.
//
fn deliverMessage(message: Message) void {
    const receiver_thread = scheduler.current().?;
    const destination = receiver_thread.message_destination;

    // Copy the message structure.
    destination.* = message;
}

////
// Asynchronously send a message to a mailbox.
//
// Arguments:
//     message: Pointer to the message to be sent.
//
pub fn send(message: *const Message) void {
    // NOTE: We need a copy in kernel space, because we
    // are potentially switching address spaces.
    const mailbox = getMailbox(message.receiver);

    if (mailbox.waiting_queue.popFirst()) |receiving_thread| {
        // There's a thread waiting to receive, wake it up.
        scheduler.new(receiving_thread);
        // Deliver the message into the receiver's address space.
        // TODO
        deliverMessage(message.*);
    } else {
        // No thread is waiting to receive, put the message in the queue.

        mailbox.messages.append(message);
    }
}

////
// Receive a message from a mailbox.
// Block if there are no messages.
//
// Arguments:
//     destination: Address where to deliver the message.
//
pub fn receive(destination: *Message) void {
    // TODO: validation, i.e. check if the thread has the right permissions.
    const mailbox = getMailbox(destination.receiver);
    // Specify where the thread wants to get the message delivered.
    const receiving_thread = scheduler.current().?;
    receiving_thread.message_destination.* = destination.*;

    if (mailbox.messages.popFirst()) |first| {
        // There's a message in the queue, deliver immediately.
        const message = first.data;
        deliverMessage(message);
        mem.allocator.destroy(first);
    } else {
        // No message in the queue, block the thread.
        scheduler.remove(receiving_thread);
        mailbox.waiting_queue.append(&receiving_thread);
    }
}
