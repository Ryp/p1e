const mmio = @import("mmio.zig");

pub const OpCode = enum(u8) {
    SoftReset = 0x00,
    CommandBufferReset = 0x01,
    AcknowledgeInterrupt = 0x02,
    SetDisplayEnabled = 0x03,
    SetDMADirection = 0x04,
    SetDisplayVRAMStart = 0x05,
    SetDisplayHorizontalRange = 0x06,
    SetDisplayVerticalRange = 0x07,
    SetDisplayMode = 0x08,
    GetGPUInfo = 0x10,
    _,
};

pub const CommandRaw = packed struct {
    payload: u24,
    op_code: OpCode,
};

const Command = union(OpCode) {
    SoftReset: packed struct(u24) {
        zero_b0_23: u24,
    },
    CommandBufferReset: packed struct(u24) {
        zero_b0_23: u24,
    },
    AcknowledgeInterrupt: packed struct(u24) {
        zero_b0_23: u24,
    },
    SetDisplayEnabled: packed struct(u24) {
        display_enabled: mmio.MMIO.Packed.DisplayState,
        zero_b1_23: u23,
    },
    SetDMADirection: packed struct(u24) {
        dma_direction: mmio.MMIO.Packed.DMADirection,
        zero_b2_23: u22,
    },
    SetDisplayVRAMStart: packed struct(u24) {
        x: u10,
        y: u9,
        zero_b19_23: u5,
    },
    SetDisplayHorizontalRange: packed struct(u24) {
        x1: u12,
        x2: u12,
    },
    SetDisplayVerticalRange: packed struct(u24) {
        y1: u10,
        y2: u10,
        zero_b20_23: u4,
    },
    SetDisplayMode: packed struct(u24) {
        horizontal_resolution1: u2,
        vertical_resolution: mmio.MMIO.Packed.VerticalResolution,
        video_mode: mmio.MMIO.Packed.VideoMode,
        display_area_color_depth: mmio.MMIO.Packed.DisplayAreaColorDepth,
        vertical_interlace: u1,
        horizontal_resolution2: u1,
        reverse_flag: u1,
        zero_b8_23: u16,
    },
    GetGPUInfo: packed struct(u24) {
        op_code: enum(u4) {
            TextureWindowSetting = 2, //02h = Read Texture Window setting  ;GP0(E2h) ;20bit/MSBs=Nothing
            DrawAreaTopLeft = 3, //     03h = Read Draw area top left      ;GP0(E3h) ;20bit/MSBs=Nothing
            DrawAreaBottomRight = 4, // 04h = Read Draw area bottom right  ;GP0(E4h) ;20bit/MSBs=Nothing
            DrawOffset = 5, //          05h = Read Draw offset             ;GP0(E5h) ;22bit
            GPUType = 7, //         07h = Read GPU Type (usually 2)    ;see "GPU Versions" chapter
            Unknown = 8, //                 08h = Unknown (Returns 00000000h) (lightgun on some GPUs?)
            _,
        },
        unused_b4_23: u20,
    },
};

pub fn make_command(raw: CommandRaw) Command {
    return switch (raw.op_code) {
        .SoftReset => .{ .SoftReset = @bitCast(raw.payload) },
        .CommandBufferReset => .{ .CommandBufferReset = @bitCast(raw.payload) },
        .AcknowledgeInterrupt => .{ .AcknowledgeInterrupt = @bitCast(raw.payload) },
        .SetDisplayEnabled => .{ .SetDisplayEnabled = @bitCast(raw.payload) },
        .SetDMADirection => .{ .SetDMADirection = @bitCast(raw.payload) },
        .SetDisplayVRAMStart => .{ .SetDisplayVRAMStart = @bitCast(raw.payload) },
        .SetDisplayHorizontalRange => .{ .SetDisplayHorizontalRange = @bitCast(raw.payload) },
        .SetDisplayVerticalRange => .{ .SetDisplayVerticalRange = @bitCast(raw.payload) },
        .SetDisplayMode => .{ .SetDisplayMode = @bitCast(raw.payload) },
        .GetGPUInfo => .{ .GetGPUInfo = @bitCast(raw.payload) },
        _ => {
            const std = @import("std");
            std.debug.print("Unknown GPU command: {x}\n", .{raw.op_code});
            unreachable;
        },
    };
}
