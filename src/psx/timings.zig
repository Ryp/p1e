// Main clock
pub const TicksPerSeconds = 33_868_800;

comptime {
    std.debug.assert(TicksPerSeconds == 44100 * 256 * 3);
}

pub const VBlankTicksNTSC = 564_480;
pub const VBlankTicksPAL = 677_376;

comptime {
    std.debug.assert(VBlankTicksNTSC == TicksPerSeconds / 60);
    std.debug.assert(VBlankTicksPAL == TicksPerSeconds / 50);
}

const std = @import("std");
