pub fn flat_texel_offset(x: usize, y: usize) usize {
    return x + y * TexelStrideY;
}

pub const TexelWidth = 1024;
pub const TexelHeight = 512;
pub const TexelSizeBytes = 2;

pub const TexelStrideX = 1;
pub const TexelStrideY = TexelWidth;

pub const SizeBytes = 1024 * 1024; // 1 MiB

comptime {
    const std = @import("std");
    std.debug.assert(SizeBytes == TexelWidth * TexelHeight * TexelSizeBytes);
}

const pixel_format = @import("pixel_format.zig");
