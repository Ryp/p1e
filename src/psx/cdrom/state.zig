const std = @import("std");

const mmio = @import("mmio.zig");
const execution = @import("execution.zig");
const image = @import("image.zig");

pub const CDROMState = struct {
    image: ?image.CDROMImage = null, // Not saved (maybe find a better mechanism later)

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
            _,
        } = .Idle,
    } = .{},

    volume_cd_L_to_spu_L: mmio.Volume = .Off,
    volume_cd_R_to_spu_R: mmio.Volume = .Off,
    volume_cd_L_to_spu_R: mmio.Volume = .Off,
    volume_cd_R_to_spu_L: mmio.Volume = .Off,

    irq_enabled_mask: u5 = 0,
    irq_requested_mask: u5 = 0,

    parameter_fifo: make_fifo(u8, 16) = .init(),
    response_fifo: make_fifo(u8, 16) = .init(),

    data_fifo: make_fifo(u8, image.RawSectorSizeBytes) = .init(),
    data_requested: bool = false, // BFRD

    read_speed_multiplier: u32 = 1,
    sector_slice_mode: execution.SectorSliceMode = .Mode2_Form1_Data_0x800,

    pending_primary_command: ?TimedCommand = null,
    pending_secondary_command: ?TimedCommand = null,

    seek_target_sector: ?u32 = null,

    const TimedCommand = struct {
        command: mmio.Command,
        ticks_remaining: u32,
    };

    const SeekTarket = struct {
        minute: u8,
        second: u8,
        frame: u8,
    };

    pub fn write(self: @This(), writer: anytype) !void {
        try writer.writeByte(@bitCast(self.stat));

        try writer.writeByte(@intFromEnum(self.volume_cd_L_to_spu_L));
        try writer.writeByte(@intFromEnum(self.volume_cd_R_to_spu_R));
        try writer.writeByte(@intFromEnum(self.volume_cd_L_to_spu_R));
        try writer.writeByte(@intFromEnum(self.volume_cd_R_to_spu_L));

        try writer.writeByte(self.irq_enabled_mask);
        try writer.writeByte(self.irq_requested_mask);

        try self.parameter_fifo.write(writer);
        try self.response_fifo.write(writer);
        try self.data_fifo.write(writer);

        try writer.writeByte(if (self.data_requested) 1 else 0);

        try writer.writeInt(@TypeOf(self.read_speed_multiplier), self.read_speed_multiplier, .little);
        try writer.writeByte(@intFromEnum(self.sector_slice_mode));

        if (self.pending_primary_command) |pending_command| {
            try writer.writeByte(1);
            try writer.writeByte(@intFromEnum(pending_command.command));
            try writer.writeInt(@TypeOf(pending_command.ticks_remaining), pending_command.ticks_remaining, .little);
        } else {
            try writer.writeByte(0);
        }

        if (self.pending_secondary_command) |pending_command| {
            try writer.writeByte(1);
            try writer.writeByte(@intFromEnum(pending_command.command));
            try writer.writeInt(@TypeOf(pending_command.ticks_remaining), pending_command.ticks_remaining, .little);
        } else {
            try writer.writeByte(0);
        }

        if (self.seek_target_sector) |seek_target_sector| {
            try writer.writeByte(1);
            try writer.writeInt(@TypeOf(seek_target_sector), seek_target_sector, .little);
        } else {
            try writer.writeByte(0);
        }
    }

    pub fn read(self: *@This(), reader: anytype) !void {
        self.stat = @bitCast(try reader.takeByte());

        self.volume_cd_L_to_spu_L = @enumFromInt(try reader.takeByte());
        self.volume_cd_R_to_spu_R = @enumFromInt(try reader.takeByte());
        self.volume_cd_L_to_spu_R = @enumFromInt(try reader.takeByte());
        self.volume_cd_R_to_spu_L = @enumFromInt(try reader.takeByte());

        self.irq_enabled_mask = @intCast(try reader.takeByte());
        self.irq_requested_mask = @intCast(try reader.takeByte());

        try self.parameter_fifo.read(reader);
        try self.response_fifo.read(reader);
        try self.data_fifo.read(reader);

        self.data_requested = try reader.takeByte() != 0;

        self.read_speed_multiplier = try reader.takeInt(@TypeOf(self.read_speed_multiplier), .little);
        self.sector_slice_mode = @enumFromInt(try reader.takeByte());

        if (try reader.takeByte() == 1) {
            var pending_command: TimedCommand = undefined;
            pending_command.command = @enumFromInt(try reader.takeByte());
            pending_command.ticks_remaining = try reader.takeInt(@TypeOf(pending_command.ticks_remaining), .little);

            self.pending_primary_command = pending_command;
        } else {
            self.pending_primary_command = null;
        }

        if (try reader.takeByte() == 1) {
            var pending_command: TimedCommand = undefined;
            pending_command.command = @enumFromInt(try reader.takeByte());
            pending_command.ticks_remaining = try reader.takeInt(@TypeOf(pending_command.ticks_remaining), .little);

            self.pending_secondary_command = pending_command;
        } else {
            self.pending_secondary_command = null;
        }

        if (try reader.takeByte() == 1) {
            self.seek_target_sector = try reader.takeInt(u32, .little);
        } else {
            self.seek_target_sector = null;
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
                elt.* = try reader.takeInt(T, .little);
            }

            self.head = try reader.takeInt(@TypeOf(self.head), .little);
            self.tail = try reader.takeInt(@TypeOf(self.tail), .little);
            self.count = try reader.takeInt(@TypeOf(self.count), .little);
        }
    };
}
