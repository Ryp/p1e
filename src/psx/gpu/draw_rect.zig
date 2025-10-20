const std = @import("std");

const PSXState = @import("../state.zig").PSXState;
const config = @import("../config.zig");

const g0 = @import("instructions_g0.zig");
const mmio = @import("mmio.zig");
const vram = @import("vram.zig");

const pixel_format = @import("pixel_format.zig");
const PackedRGB8 = pixel_format.PackedRGB8;
const PackedRGB5A1 = pixel_format.PackedRGB5A1;

pub fn execute(psx: *PSXState, draw_rect: g0.DrawRectOpCode, command_bytes: []const u8) void {
    if (config.enable_gpu_debug) {
        std.debug.print("DrawRect: {}\n", .{draw_rect});
    }

    switch (draw_rect.is_textured) {
        true => {
            const rect_textured = std.mem.bytesAsValue(g0.DrawRectTextured, command_bytes);

            const extent: g0.PackedVertexPos = switch (draw_rect.size) {
                ._1x1 => .{ .x = 1, .y = 1 },
                ._8x8 => .{ .x = 8, .y = 8 },
                ._16x16 => .{ .x = 16, .y = 16 },
                .Variable => std.mem.bytesAsValue(g0.DrawRectTexturedVariable, command_bytes).extent,
            };

            draw_rectangle_textured(psx, rect_textured.position_top_left, .{ .x = extent.x, .y = extent.y }, rect_textured.color, rect_textured.position_texcoord, rect_textured.palette, draw_rect.is_semi_transparent);
        },
        false => {
            const rect_monochrome = std.mem.bytesAsValue(g0.DrawRectMonochrome, command_bytes);

            std.debug.assert(!draw_rect.is_semi_transparent);

            const extent: g0.PackedVertexPos = switch (draw_rect.size) {
                ._1x1 => .{ .x = 1, .y = 1 },
                ._8x8 => .{ .x = 8, .y = 8 },
                ._16x16 => .{ .x = 16, .y = 16 },
                .Variable => std.mem.bytesAsValue(g0.DrawRectMonochromeVariable, command_bytes).extent,
            };

            draw_rectangle_monochrome(psx, rect_monochrome.position_top_left, .{ .x = extent.x, .y = extent.y }, rect_monochrome.color);
        },
    }
}

// FIXME Copy-pasted from draw_poly. Yuck
fn draw_rectangle_textured(psx: *PSXState, offset: g0.PackedVertexPos, size: g0.PackedVertexPos, color: PackedRGB8, offset_texcoord: g0.PackedTexCoord, palette: g0.PackedClut, is_semi_transparent: bool) void {
    _ = color; // FIXME

    for (0..size.y) |local_y| {
        for (0..size.x) |local_x| {
            const x = local_x + offset.x;
            const y = local_y + offset.y;

            var output: pixel_format.PackedRGB5A1 = undefined;
            const vram_output_offset = vram.flat_texel_offset(x, y);

            // FIXME
            const page_x_offset = @as(u32, psx.mmio.gpu.GPUSTAT.texture_x_base) * 64;
            const page_y_offset = @as(u32, psx.mmio.gpu.GPUSTAT.texture_y_base) * 256;

            var tx: u32 = (@as(u32, @intCast(local_x)) + offset_texcoord.x) % 256;
            var ty: u32 = (@as(u32, @intCast(local_y)) + offset_texcoord.y) % 256;

            std.debug.assert(tx < 256);
            std.debug.assert(ty < 256);

            // FIXME
            tx = (tx & ~psx.gpu.regs.texture_window_x_mask) | (psx.gpu.regs.texture_window_x_offset & psx.gpu.regs.texture_window_x_mask);
            ty = (ty & ~psx.gpu.regs.texture_window_y_mask) | (psx.gpu.regs.texture_window_y_offset & psx.gpu.regs.texture_window_y_mask);

            switch (psx.mmio.gpu.GPUSTAT.texture_page_colors) {
                ._4bits => {
                    std.debug.assert(palette.zero == 0);

                    const index_texel_offset = vram.flat_texel_offset(page_x_offset + tx / 4, page_y_offset + ty);
                    const index_chunk: u16 = @bitCast(psx.gpu.vram_texels[index_texel_offset]);
                    const index: u4 = @truncate(index_chunk >> @intCast((tx % 4) * 4));

                    const clut_x = @as(u32, palette.x) * 16;
                    const clut_y = @as(u32, palette.y);
                    const clut_offset = vram.flat_texel_offset(clut_x, clut_y);
                    const clut_slice = psx.gpu.vram_texels[clut_offset..][0..16];

                    output = clut_slice[index];
                },
                ._8bits => {
                    @panic("8Bits Not implemented");
                },
                ._15bits => {
                    const texel_offset = vram.flat_texel_offset(page_x_offset + tx, page_y_offset + ty);

                    output = psx.gpu.vram_texels[texel_offset];
                },
                .Reserved => @panic("Invalid texture page color mode"),
            }

            if (output == pixel_format.PackedRGB5A1{ .r = 0, .g = 0, .b = 0, .a = 0 }) {
                continue;
            } else if (is_semi_transparent and output.a == 1) {
                const background = psx.gpu.vram_texels[vram_output_offset];

                const poly = @import("draw_poly.zig");
                psx.gpu.vram_texels[vram_output_offset] = poly.compute_alpha_blending(background, output, psx.mmio.gpu.GPUSTAT.semi_transparency_mode);
            } else {
                psx.gpu.vram_texels[vram_output_offset] = output;
            }
        }
    }
}

fn draw_rectangle_monochrome(psx: *PSXState, offset: g0.PackedVertexPos, size: g0.PackedVertexPos, color: PackedRGB8) void {
    const fill_color_rgb5 = pixel_format.convert_rgb8_to_rgb5a1(color, 0);

    for (0..size.y) |y| {
        const flat_offset_y = vram.flat_texel_offset(0, offset.y + y);

        const vram_texel_line = psx.gpu.vram_texels[flat_offset_y .. flat_offset_y + vram.TexelStrideY];

        const vram_texel_line_rect = vram_texel_line[offset.x .. offset.x + size.x];

        @memset(vram_texel_line_rect, fill_color_rgb5);
    }
}
