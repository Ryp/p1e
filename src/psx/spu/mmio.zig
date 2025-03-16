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

    pub const Packed = MMIO_SPU;

    const SizeBytes = mmio.MMIO_Expansion2_Offset - Offset;

    comptime {
        std.debug.assert(@sizeOf(Packed) == SizeBytes);
    }
};

const MMIO_SPU = packed struct {
    _unused: u8192 = undefined,
};
