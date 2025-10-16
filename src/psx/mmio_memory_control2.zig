const std = @import("std");

const mmio = @import("mmio.zig");
const irq = @import("mmio_interrupts.zig");

const PSXState = @import("state.zig").PSXState;

pub fn load_mmio_generic(comptime T: type, psx: *PSXState, offset: u29) T {
    std.debug.assert(offset >= MMIO.Offset);
    std.debug.assert(offset < MMIO.OffsetEnd);

    std.debug.assert(T != u8);

    const type_slice = mmio.get_mutable_mmio_slice(T, psx, offset);

    switch (offset) {
        MMIO.RamSize_Offset => {
            return std.mem.readInt(T, type_slice, .little);
        },
        else => @panic("Invalid MC2 MMIO load offset"),
    }
}

pub fn store_mmio_generic(comptime T: type, psx: *PSXState, offset: u29, value: T) void {
    std.debug.assert(offset >= MMIO.Offset);
    std.debug.assert(offset < MMIO.OffsetEnd);

    std.debug.assert(T != u8);

    const type_slice = mmio.get_mutable_mmio_slice(T, psx, offset);

    switch (offset) {
        MMIO.RamSize_Offset => {
            std.debug.assert(value == 0x0B88);
            std.mem.writeInt(T, type_slice, value, .little);
        },
        else => @panic("Invalid MC2 MMIO store offset"),
    }
}

pub const MMIO = struct {
    pub const Offset = 0x1f801060;
    pub const OffsetEnd = Offset + SizeBytes;

    const SizeBytes = irq.MMIO.Offset - Offset;

    comptime {
        std.debug.assert(@sizeOf(Packed) == SizeBytes);
    }

    const RamSize_Offset = 0x1f801060;

    pub const Packed = packed struct {
        ram_size: RamSize = .{},
        _unused: u112 = undefined,

        const RamSize = packed struct(u16) {
            unknown_b0_2: u3 = undefined, //   0-2   Unknown (no effect)
            b3: u1 = undefined, //   3     Crashes when zero (except PU-7 and EARLY-PU-8, which <do> use bit3=0)
            unknown_b4_6: u3 = undefined, //   4-6   Unknown (no effect)
            b7: u1 = undefined, //   7     Delay on simultaneous CODE+DATA fetch from RAM (0=None, 1=One Cycle)
            unknown_b8: u1 = undefined, //   8     Unknown (no effect) (should be set for 8MB, cleared for 2MB)
            memory_window_b9_11: u3 = undefined, //   9-11  Define 8MB Memory Window (first 8MB of KUSEG,KSEG0,KSEG1)
            unknown_b12_15: u4 = undefined, //   12-15 Unknown (no effect)
        };
    };
};
