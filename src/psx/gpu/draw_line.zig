const std = @import("std");

const PSXState = @import("../state.zig").PSXState;
const config = @import("../config.zig");

const g0 = @import("instructions_g0.zig");
const vram = @import("vram.zig");

const pixel_format = @import("pixel_format.zig");
const PackedRGB8 = pixel_format.PackedRGB8;
const PackedRGB5A1 = pixel_format.PackedRGB5A1;

const u32_2 = @Vector(2, u32);
const i32_2 = @Vector(2, i32);

pub fn execute(psx: *PSXState, draw_line: g0.DrawLineOpCode, command_bytes: []const u8) void {
    if (config.enable_gpu_debug) {
        std.debug.print("DrawLine: {}\n", .{draw_line});
    }

    std.debug.print("Draw line unimplemented!\n", .{});

    _ = psx;
    _ = command_bytes;

    if (draw_line.is_poly_line) {
        @panic("Poly lines not implemented and will crash!");
    }
}
