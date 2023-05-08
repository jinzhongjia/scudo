const std = @import("std");
const interrupt = @import("interrupt.zig");
const tty = @import("tty.zig");
const cpu = @import("cpu");

const x86 = cpu.x86;
const builtin = std.builtin;

// Registered syscall handlers.
pub var handlers = [_]*const fn () void{
    // SYSCALL(exit), // 0
    // SYSCALL(ipc.send), // 1
    // SYSCALL(ipc.receive), // 2
    // SYSCALL(interrupt.subscribeIRQ), // 3
    SYSCALL(x86.assembly.inb), // 4
    SYSCALL(x86.assembly.outb), // 5
    // SYSCALL(map), // 6
    // SYSCALL(createThread), // 7
    SYSCALL(println),
    SYSCALL(println),
    SYSCALL(println),
    SYSCALL(println),
    SYSCALL(println),
    SYSCALL(println),
    SYSCALL(println),
};

fn println() void {
    tty.println("test", .{});
}

////
// Transform a normal function (with standard calling convention) into
// a syscall handler, which takes parameters from the context of the
// user thread that called it. Handles return values as well.
//
// Arguments:
//     function: The function to be transformed into a syscall.
//
// Returns:
//     A syscall handler that wraps the given function.
//
fn SYSCALL(comptime function: anytype) fn () void {
    const signature = @TypeOf(function);
    const params: []const builtin.Type.Fn.Param = @typeInfo(signature).Fn.params;

    return struct {
        // Return the n-th argument passed to the function.
        fn arg(comptime n: u8) if (params[n].type) |param_type| param_type else null {
            if (params[n].type) |param_type| {
                return getArg(n, param_type);
            }
        }

        // Wrapper.
        fn syscall() void {
            // Fetch the right number of arguments and call the function.
            const result = switch (params.len) {
                0 => function(),
                1 => function(arg(0)),
                2 => function(arg(0), arg(1)),
                3 => function(arg(0), arg(1), arg(2)),
                4 => function(arg(0), arg(1), arg(2), arg(3)),
                5 => function(arg(0), arg(1), arg(2), arg(3), arg(4)),
                6 => function(arg(0), arg(1), arg(2), arg(3), arg(4), arg(5)),
                else => unreachable,
            };

            // Handle the return value if present.
            if (@TypeOf(result) != void) {
                interrupt.context.setReturnValue(result);
            }
        }
    }.syscall;
}

////
// Fetch the n-th syscall argument of type T from the caller context.
//
// Arguments:
//     n: Argument index.
//     T: Argument type.
//
// Returns:
//     The syscall argument casted to the requested type.
//
inline fn getArg(comptime n: u8, comptime T: type) T {
    const value = switch (n) {
        0 => interrupt.context.registers.ecx,
        1 => interrupt.context.registers.edx,
        2 => interrupt.context.registers.ebx,
        3 => interrupt.context.registers.esi,
        4 => interrupt.context.registers.edi,
        5 => interrupt.context.registers.ebp,
        else => unreachable,
    };

    const typeinfo = @typeInfo(T);

    switch (typeinfo) {
        .Bool => {
            return value != 0;
        },
        .Int => {
            return @intCast(T, value);
        },
        .Pointer => {
            return @intToPtr(T, value);
        },
        else => {
            tty.panic("syscall args pass failed, it only can be Int and Pointer", null);
        },
    }
}

////
// Handle the call of an invalid syscall.
//
pub fn invalid() noreturn {
    const n = interrupt.context.registers.eax;
    tty.panic("invalid syscall number {d}", .{n});

    // TODO: kill the current process and go on.
}

///////////////////////////
////  Syscall numbers  ////
///////////////////////////

pub const Syscall = enum(usize) {
    exit = 0,
    send = 1,
    receive = 2,
    subscribeIRQ = 3,
    inb = 4,
    outb = 5,
    map = 6,
    createThread = 7,
    print = 8,
};

/////////////////////////
////  Syscall stubs  ////
/////////////////////////

pub inline fn syscall0(number: Syscall) usize {
    return asm volatile ("int $0x80"
        : [ret] "={eax}" (-> usize),
        : [number] "{eax}" (number),
    );
}

pub inline fn syscall1(number: Syscall, arg1: usize) usize {
    return asm volatile ("int $0x80"
        : [ret] "={eax}" (-> usize),
        : [number] "{eax}" (number),
          [arg1] "{ecx}" (arg1),
    );
}

pub inline fn syscall2(number: Syscall, arg1: usize, arg2: usize) usize {
    return asm volatile ("int $0x80"
        : [ret] "={eax}" (-> usize),
        : [number] "{eax}" (number),
          [arg1] "{ecx}" (arg1),
          [arg2] "{edx}" (arg2),
    );
}

pub inline fn syscall3(number: Syscall, arg1: usize, arg2: usize, arg3: usize) usize {
    return asm volatile ("int $0x80"
        : [ret] "={eax}" (-> usize),
        : [number] "{eax}" (number),
          [arg1] "{ecx}" (arg1),
          [arg2] "{edx}" (arg2),
          [arg3] "{ebx}" (arg3),
    );
}

pub inline fn syscall4(number: Syscall, arg1: usize, arg2: usize, arg3: usize, arg4: usize) usize {
    return asm volatile ("int $0x80"
        : [ret] "={eax}" (-> usize),
        : [number] "{eax}" (number),
          [arg1] "{ecx}" (arg1),
          [arg2] "{edx}" (arg2),
          [arg3] "{ebx}" (arg3),
          [arg4] "{esi}" (arg4),
    );
}

pub inline fn syscall5(
    number: Syscall,
    arg1: usize,
    arg2: usize,
    arg3: usize,
    arg4: usize,
    arg5: usize,
) usize {
    return asm volatile ("int $0x80"
        : [ret] "={eax}" (-> usize),
        : [number] "{eax}" (number),
          [arg1] "{ecx}" (arg1),
          [arg2] "{edx}" (arg2),
          [arg3] "{ebx}" (arg3),
          [arg4] "{esi}" (arg4),
          [arg5] "{edi}" (arg5),
    );
}

pub inline fn syscall6(
    number: Syscall,
    arg1: usize,
    arg2: usize,
    arg3: usize,
    arg4: usize,
    arg5: usize,
    arg6: usize,
) usize {
    return asm volatile ("int $0x80"
        : [ret] "={eax}" (-> usize),
        : [number] "{eax}" (number),
          [arg1] "{ecx}" (arg1),
          [arg2] "{edx}" (arg2),
          [arg3] "{ebx}" (arg3),
          [arg4] "{esi}" (arg4),
          [arg5] "{edi}" (arg5),
          [arg6] "{ebp}" (arg6),
    );
}
