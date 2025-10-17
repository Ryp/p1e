const std = @import("std");

const PSXState = @import("../state.zig").PSXState;

const g0 = @import("instructions_g0.zig");
const mmio = @import("mmio.zig");

const pixel_format = @import("pixel_format.zig");
const PackedRGB8 = pixel_format.PackedRGB8;
const PackedRGB5A1 = pixel_format.PackedRGB5A1;

// FIXME dedup
const VRAMTextureWidth = 1024;
const VRAMTextureHeight = 512;
const stride_y = VRAMTextureWidth; // FIXME

pub fn execute(psx: *PSXState, draw_rect: g0.DrawRectOpCode, command_bytes: []const u8) void {
    // FIXME Switch over branches (size last)
    switch (draw_rect.size) {
        ._1x1, ._8x8, ._16x16 => |size| {
            std.debug.assert(!draw_rect.is_semi_transparent); // FIXME

            const px_size: u5 = switch (size) {
                ._1x1 => 1,
                ._8x8 => 8,
                ._16x16 => 16,
                .Variable => unreachable,
            };

            if (draw_rect.is_textured) {
                const rect_textured = std.mem.bytesAsValue(g0.DrawRectTextured, command_bytes);
                std.debug.print("DrawRectTextured: {any}\n", .{rect_textured});

                draw_rectangle_textured(psx, rect_textured.position_top_left, .{ .x = px_size, .y = px_size }, rect_textured.color, rect_textured.position_texcoord, rect_textured.palette);
            } else {
                const rect_monochrome = std.mem.bytesAsValue(g0.DrawRectMonochrome, command_bytes);

                draw_rectangle(psx, rect_monochrome.position_top_left, .{ .x = px_size, .y = px_size }, rect_monochrome.color);
            }
        },
        .Variable => {
            if (draw_rect.is_textured) {
                const rect_monochrome_variable = std.mem.bytesAsValue(g0.DrawRectMonochromeVariable, command_bytes);
                std.debug.print("DrawRectMonochromeVariable: {any}\n", .{rect_monochrome_variable});

                @panic("DrawRectMonochromeVariable unsupported");
            } else {
                const rect_textured_variable = std.mem.bytesAsValue(g0.DrawRectTexturedVariable, command_bytes);
                std.debug.print("DrawRectTexturedVariable: {any}\n", .{rect_textured_variable});

                @panic("DrawRectTexturedVariable unsupported");
            }
        },
    }
}

fn draw_rectangle(psx: *PSXState, offset: g0.PackedVertexPos, size: g0.PackedVertexPos, color: PackedRGB8) void {
    const fill_color_rgb5 = pixel_format.convert_rgb8_to_rgb5a1(color, 0);

    const vram_typed = std.mem.bytesAsSlice(PackedRGB5A1, psx.gpu.vram);

    for (0..size.y) |y| {
        const offset_y = (offset.y + y) * stride_y;

        const vram_type_line = vram_typed[offset_y .. offset_y + stride_y];

        const vram_type_line_rect = vram_type_line[offset.x .. offset.x + size.x];

        @memset(vram_type_line_rect, fill_color_rgb5);
    }
}

fn draw_rectangle_textured(psx: *PSXState, offset: g0.PackedVertexPos, size: g0.PackedVertexPos, color: PackedRGB8, offset_texcoord: g0.PackedVertexPos, palette: g0.PackedClut) void {
    const is_semi_transparent = false; // FIXME
    const vram_typed = std.mem.bytesAsSlice(PackedRGB5A1, psx.gpu.vram);

    for (0..size.y) |local_y| {
        for (0..size.x) |local_x| {
            const x = local_x + offset.x;
            const y = local_y + offset.y;

            var output: pixel_format.PackedRGB5A1 = undefined;
            const vram_output_offset = y * stride_y + x;

            // FIXME
            const page_x_offset = @as(u32, psx.gpu.GPUSTAT.texture_x_base) * 64;
            const page_y_offset = @as(u32, psx.gpu.GPUSTAT.texture_y_base) * 256;

            var tx: u32 = local_x + offset_texcoord.x % 256;
            var ty: u32 = local_y + offset_texcoord.y % 256;

            std.debug.assert(tx < 256);
            std.debug.assert(ty < 256);

            // FIXME
            tx = (tx & ~psx.gpu.regs.texture_window_x_mask) | (psx.gpu.regs.texture_window_x_offset & psx.gpu.regs.texture_window_x_mask);
            ty = (ty & ~psx.gpu.regs.texture_window_y_mask) | (psx.gpu.regs.texture_window_y_offset & psx.gpu.regs.texture_window_y_mask);

            switch (psx.gpu.GPUSTAT.texture_page_colors) {
                ._4bits => {
                    std.debug.assert(palette.clut.zero == 0);
                    const clut_x = @as(u32, palette.clut.x) * 16;
                    const clut_y = @as(u32, palette.clut.y);

                    const clut_slice = vram_typed[clut_y * stride_y + clut_x ..][0..16];

                    const clut_chunk: u16 = @bitCast(vram_typed[page_x_offset + tx / 4 + (page_y_offset + ty) * stride_y]);
                    const clut_index: u4 = @truncate(clut_chunk >> @intCast((tx % 4) * 4));

                    output = clut_slice[clut_index];
                },
                ._8bits => {
                    @panic("8Bits Not implemented");
                },
                ._15bits => {
                    tx = (tx + page_x_offset);
                    ty = (ty + page_y_offset);

                    output = vram_typed[tx + ty * stride_y];
                },
                .Reserved => @panic("Invalid texture page color mode"),
            }

            if (output == pixel_format.PackedRGB5A1{ .r = 0, .g = 0, .b = 0, .a = 0 }) {
                continue;
            } else if (is_semi_transparent and output.a == 1) {
                const background = vram_typed[vram_output_offset];

                const poly = @import("draw_poly.zig");
                vram_typed[vram_output_offset] = poly.compute_alpha_blending(background, output, psx.gpu.GPUSTAT.semi_transparency_mode);
            } else {
                vram_typed[vram_output_offset] = output;
            }
        }
    }
}
