const std = @import("std");

const PSXState = @import("../state.zig").PSXState;
const mmio = @import("../mmio.zig");

const config = @import("../config.zig");

pub fn load_mmio_generic(comptime T: type, psx: *PSXState, offset: u29) T {
    _ = psx;
    _ = offset;

    if (config.enable_debug_print) {
        std.debug.print("MMIO SPU load ignored\n", .{}); // FIXME
    }

    return 0;
}

pub fn store_mmio_generic(comptime T: type, psx: *PSXState, offset: u29, value: T) void {
    _ = psx;
    _ = offset;
    _ = value;

    if (config.enable_debug_print) {
        std.debug.print("MMIO SPU store ignored\n", .{}); // FIXME
    }
}

pub const MMIO = struct {
    pub const Offset = 0x1f801c00;
    pub const OffsetEnd = Offset + SizeBytes;

    const SizeBytes = mmio.Expansion2_MMIO.Offset - Offset;

    comptime {
        std.debug.assert(@sizeOf(Packed) == SizeBytes);
    }

    const MMIO_MainVolume_Left = 0x1f801d80;
    const MMIO_MainVolume_Right = 0x1f801d82;

    pub const Packed = packed struct {
        _unused: u8192 = undefined,
    };
};
