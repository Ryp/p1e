const std = @import("std");

const config = @import("../config.zig");

const PSXState = @import("../state.zig").PSXState;

pub fn execute_ctc(psx: *PSXState, register_index: u5, value: u32) void {
    if (config.enable_gte_debug) {
        std.debug.print("ctc2 mv {x} to ctrl register {}\n", .{ value, register_index });
    }

    psx.gte.ctrl_regs[register_index] = value;
}
