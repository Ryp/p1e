const std = @import("std");

const MMIO = @import("mmio.zig").MMIO.Packed;
const execution = @import("execution.zig");

pub const CDROMState = struct {
    // This is returned by most commands
    stat: packed struct(u8) {
        has_error: bool = false, // 0  Error         Invalid Command/parameters (followed by Error Byte)
        is_spindle_motor_on: bool = false, // 1  Spindle Motor (0=Motor off, or in spin-up phase, 1=Motor on)
        has_seek_error: bool = false, // 2  SeekError     (0=Okay, 1=Seek error)     (followed by Error Byte)
        has_id_error: bool = false, // 3  IdError       (0=Okay, 1=GetID denied) (also set when Setmode.Bit4=1)
        is_shell_open: bool = false, // 4  ShellOpen     Once shell open (0=Closed, 1=Is/was Open)
        main_state: enum(u3) { // Those three last bits are mutually exclusive
            Idle = 0,
            Reading = 0b001, // 5  Read          Reading data sectors
            Seeking = 0b010, // 6  Seek          Seeking
            PlayingCDDA = 0b100, // 7  Play          Playing CD-DA
        } = .Idle,
    } = .{},

    irq_enabled_mask: u5 = 0,
    irq_requested_mask: u5 = 0,

    parameter_fifo: make_fifo(u8, 16) = .init(),
    response_fifo: make_fifo(u8, 16) = .init(),

    active_timed_command: ?TimedCommand = null,

    seek_target: ?SeekTarket = null,

    const TimedCommand = struct {
        command: execution.Command,
        ticks_remaining: u32,
    };

    const SeekTarket = struct {
        minute: u8,
        second: u8,
        frame: u8,
    };

    pub fn write(self: @This(), writer: anytype) !void {
        try writer.writeByte(@bitCast(self.stat));

        try writer.writeByte(self.irq_enabled_mask);
        try writer.writeByte(self.irq_requested_mask);

        try self.parameter_fifo.write(writer);
        try self.response_fifo.write(writer);

        if (self.active_timed_command) |active_timed_command| {
            try writer.writeByte(1);
            try writer.writeByte(@intFromEnum(active_timed_command.command));
            try writer.writeInt(@TypeOf(active_timed_command.ticks_remaining), active_timed_command.ticks_remaining, .little);
        } else {
            try writer.writeByte(0);
        }

        if (self.seek_target) |seek_target| {
            try writer.writeByte(1);
            try writer.writeByte(seek_target.minute);
            try writer.writeByte(seek_target.second);
            try writer.writeByte(seek_target.frame);
        } else {
            try writer.writeByte(0);
        }
    }

    pub fn read(self: *@This(), reader: anytype) !void {
        self.stat = @bitCast(try reader.readByte());

        self.irq_enabled_mask = @intCast(try reader.readByte());
        self.irq_requested_mask = @intCast(try reader.readByte());

        try self.parameter_fifo.read(reader);
        try self.response_fifo.read(reader);

        if (try reader.readByte() == 1) {
            var active_timed_command: TimedCommand = undefined;
            active_timed_command.command = @enumFromInt(try reader.readByte());
            active_timed_command.ticks_remaining = try reader.readInt(@TypeOf(active_timed_command.ticks_remaining), .little);

            self.active_timed_command = active_timed_command;
        } else {
            self.active_timed_command = null;
        }

        if (try reader.readByte() == 1) {
            var seek_target: SeekTarket = undefined;
            seek_target.minute = try reader.readByte();
            seek_target.second = try reader.readByte();
            seek_target.frame = try reader.readByte();

            self.seek_target = seek_target;
        } else {
            self.seek_target = null;
        }
    }
};

// AI-gen static fifo implementation
// This used to be in the standard library before 15.0 then got removed.
fn make_fifo(comptime T: type, comptime size: u32) type {
    return struct {
        buffer: [size]T = undefined,
        head: u32 = 0,
        tail: u32 = 0,
        count: u32 = 0,

        pub fn init() @This() {
            return .{};
        }

        pub fn is_empty(self: @This()) bool {
            return self.count == 0;
        }

        pub fn is_full(self: @This()) bool {
            return self.count == size;
        }

        pub fn push(self: *@This(), value: T) !void {
            if (self.is_full()) {
                return error.FifoFull;
            }
            self.buffer[self.tail] = value;
            self.tail = (self.tail + 1) % size;
            self.count += 1;
        }

        pub fn pop(self: *@This()) !T {
            if (self.is_empty()) {
                return error.FifoEmpty;
            }
            const value = self.buffer[self.head];
            self.head = (self.head + 1) % size;
            self.count -= 1;
            return value;
        }

        pub fn peek(self: @This()) !T {
            if (self.is_empty()) {
                return error.FifoEmpty;
            }
            return self.buffer[self.head];
        }

        pub fn discard(self: *@This()) void {
            self.head = 0;
            self.tail = 0;
            self.count = 0;
        }

        pub fn write(self: @This(), writer: anytype) !void {
            for (self.buffer) |elt| {
                try writer.writeInt(T, elt, .little);
            }

            try writer.writeInt(@TypeOf(self.head), self.head, .little);
            try writer.writeInt(@TypeOf(self.tail), self.tail, .little);
            try writer.writeInt(@TypeOf(self.count), self.count, .little);
        }

        pub fn read(self: *@This(), reader: anytype) !void {
            for (&self.buffer) |*elt| {
                elt.* = try reader.readInt(T, .little);
            }

            self.head = try reader.readInt(@TypeOf(self.head), .little);
            self.tail = try reader.readInt(@TypeOf(self.tail), .little);
            self.count = try reader.readInt(@TypeOf(self.count), .little);
        }
    };
}
