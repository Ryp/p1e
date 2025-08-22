const state = @import("state.zig");
const f32_3 = state.f32_3;

pub const PackedRGB8 = packed struct(u24) {
    r: u8,
    g: u8,
    b: u8,
};

pub const PackedRGB5A1 = packed struct(u16) {
    r: u5,
    g: u5,
    b: u5,
    a: u1,
};

pub const PackedRGBA8 = packed struct(u32) {
    r: u8,
    g: u8,
    b: u8,
    a: u8,
};

pub fn convert_rgb8_to_rgb5a1(color: PackedRGB8, alpha: u1) PackedRGB5A1 {
    return .{
        .r = @intFromFloat(@as(f32, @floatFromInt(color.r)) / 255.0 * 31.0),
        .g = @intFromFloat(@as(f32, @floatFromInt(color.g)) / 255.0 * 31.0),
        .b = @intFromFloat(@as(f32, @floatFromInt(color.b)) / 255.0 * 31.0),
        .a = alpha,
    };
}

pub fn convert_rgb5a1_to_rgb_f32(color: PackedRGB5A1) struct { f32_3, u1 } {
    return .{ .{
        @as(f32, @floatFromInt(color.r)) / 31.0,
        @as(f32, @floatFromInt(color.g)) / 31.0,
        @as(f32, @floatFromInt(color.b)) / 31.0,
    }, color.a };
}

pub fn convert_rgb_f32_to_rgb5a1(color: f32_3, alpha: u1) PackedRGB5A1 {
    return .{
        .r = @intFromFloat(color[0] * 31.0),
        .g = @intFromFloat(color[1] * 31.0),
        .b = @intFromFloat(color[2] * 31.0),
        .a = alpha,
    };
}

pub fn convert_rgb5a1_to_rgba8(color: PackedRGB5A1) PackedRGBA8 {
    return .{
        .r = @intFromFloat(@as(f32, @floatFromInt(color.r)) / 31.0 * 255.0),
        .g = @intFromFloat(@as(f32, @floatFromInt(color.g)) / 31.0 * 255.0),
        .b = @intFromFloat(@as(f32, @floatFromInt(color.b)) / 31.0 * 255.0),
        .a = 255 * @as(u8, color.a),
    };
}
