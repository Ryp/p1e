const std = @import("std");

const MMIO = @import("mmio.zig").MMIO.Packed;

// Static fifo implementation
// This used to be in the standard library before 15.0 then got removed.
fn make_fifo(comptime T: type, comptime size: usize) type {
    return struct {
        buffer: [size]T = undefined,
        head: usize = 0,
        tail: usize = 0,
        count: usize = 0,
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
    };
}

pub const CDROMState = struct {
    irq_enabled_mask: u5 = 0,
    irq_requested_mask: u5 = 0,

    stat: packed struct(u8) {
        has_error: bool = false, // 0  Error         Invalid Command/parameters (followed by Error Byte)
        is_spindle_motor_on: bool = true, // 1  Spindle Motor (0=Motor off, or in spin-up phase, 1=Motor on)
        has_seek_error: bool = false, // 2  SeekError     (0=Okay, 1=Seek error)     (followed by Error Byte)
        has_id_error: bool = false, // 3  IdError       (0=Okay, 1=GetID denied) (also set when Setmode.Bit4=1)
        is_shell_open: bool = false, // 4  ShellOpen     Once shell open (0=Closed, 1=Is/was Open)
        // Those three last bits are mutually exclusive
        is_reading: bool = false, // 5  Read          Reading data sectors
        is_seeking: bool = false, // 6  Seek          Seeking
        is_playing_cd_da: bool = false, // 7  Play          Playing CD-DA
    } = .{},

    parameter_fifo: make_fifo(u8, 16) = .init(),
    response_fifo: make_fifo(u8, 16) = .init(),

    // volume_cd_L_to_spu_L: MMIO.Volume = .Normal,
    // volume_cd_L_to_spu_R: MMIO.Volume = .Normal,
    // volume_cd_R_to_spu_R: MMIO.Volume = .Normal,
    // volume_cd_R_to_spu_L: MMIO.Volume = .Normal,

    pub fn write(self: @This(), writer: anytype) !void {
        // FIXME
        _ = self;
        _ = writer;
    }

    pub fn read(self: *@This(), reader: anytype) !void {
        // FIXME
        _ = self;
        _ = reader;
    }
};
