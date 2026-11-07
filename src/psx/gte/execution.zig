const std = @import("std");

const config = @import("../config.zig");

const PSXState = @import("../state.zig").PSXState;

pub fn execute_ctc(psx: *PSXState, register_index: u5, value: u32) void {
    if (config.enable_gte_debug) {
        std.debug.print("ctc2 mv {x} to ctrl register {}\n", .{ value, register_index });
    }

    psx.gte.store_ctrl_reg(@fromBackingInt(register_index), value);
}

pub fn execute_lwc(psx: *PSXState, register_index: u5, value: u32) void {
    if (config.enable_gte_debug) {
        std.debug.print("lwc2 mv {x} to data register {}\n", .{ value, register_index });
    }

    psx.gte.store_data_reg(@fromBackingInt(register_index), value);
}

pub fn execute_cop(psx: *PSXState, immediate: u25) void {
    _ = psx;
    _ = immediate;

    @panic("Unimplemented");
}
