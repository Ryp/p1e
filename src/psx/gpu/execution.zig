const std = @import("std");

const PSXState = @import("../state.zig").PSXState;

const g0 = @import("instructions_g0.zig");
const g1 = @import("instructions_g1.zig");

const config = @import("../config.zig");

// FIXME be very careful with endianness here
pub fn store_gp0_u32(psx: *PSXState, value: u32) void {
    if (config.enable_gpu_debug) {
        std.debug.print("GP0 write: 0x{x:0>8}\n", .{value});
    }

    if (psx.gpu.gp0_pending_command == null and psx.gpu.gp0_copy_mode == null) {
        const op_code: g0.OpCode = @enumFromInt(value >> 24);
        const command_size_bytes = g0.command_size_bytes(op_code);

        psx.gpu.gp0_pending_command = .{
            .op_code = op_code,
            .current_byte_index = 0,
            .command_size_bytes = command_size_bytes,
        };

        if (config.enable_gpu_debug) {
            std.debug.print("New GP0 command: op = {}, bytes = {}\n", .{ op_code, command_size_bytes });
        }
    }

    if (psx.gpu.gp0_copy_mode) |*copy_mode| {
        for (0..2) |_| {
            // FIXME Write!!!
            copy_mode.index_x += 1;

            if (copy_mode.index_x == copy_mode.command.extent_x) {
                copy_mode.index_x = 0;
                copy_mode.index_y += 1;
            }

            // Check for end condition
            if (copy_mode.index_y == copy_mode.command.extent_y) {
                psx.gpu.gp0_copy_mode = null;
                break;
            }
        }
    } else {
        // We have to have a valid command at this point
        const pending_command = if (psx.gpu.gp0_pending_command) |*pending_command| pending_command else unreachable;

        // Write current u32 to the pending command buffer
        std.mem.writeInt(u32, psx.gpu.gp0_pending_bytes[pending_command.current_byte_index..][0..4], value, .little);

        pending_command.current_byte_index += @sizeOf(u32);

        // Check if we wrote enough bytes to dispatch a command
        if (pending_command.current_byte_index == pending_command.command_size_bytes) {
            const command_bytes = psx.gpu.gp0_pending_bytes[0..pending_command.command_size_bytes];

            execute_gp0_command(psx, pending_command.op_code, command_bytes);

            psx.gpu.gp0_pending_command = null;
        }
    }
}

fn execute_gp0_command(psx: *PSXState, op_code: g0.OpCode, command_bytes: []u8) void {
    switch (op_code) {
        .Noop => {
            const noop = std.mem.bytesAsValue(g0.Noop, command_bytes);
            _ = noop.unknown_b0_23;

            // Do nothing!
        },
        .ClearTextureCache => {
            const clear_texture_cache = std.mem.bytesAsValue(g0.ClearTextureCache, command_bytes);
            std.debug.assert(clear_texture_cache.zero_b0_23 == 0);

            // FIXME ignore for now
            // unreachable; // FIXME
        },
        .DrawTriangleMonochromeOpaque, .DrawTriangleMonochromeTransparent => {
            const draw_triangle_monochrome = std.mem.bytesAsValue(g0.DrawTriangleMonochrome, command_bytes);
            _ = draw_triangle_monochrome;
            // unreachable; // FIXME
        },
        .DrawQuadMonochromeOpaque, .DrawQuadMonochromeTransparent => {
            const draw_quad_monochrome = std.mem.bytesAsValue(g0.DrawQuadMonochrome, command_bytes);
            _ = draw_quad_monochrome;
            //unreachable; // FIXME
        },
        .DrawTriangleTexturedOpaqueBlended, .DrawTriangleTexturedOpaque, .DrawTriangleTexturedTransparentBlended, .DrawTriangleTexturedTransparent => {
            const draw_triangle_textured = std.mem.bytesAsValue(g0.DrawTriangleTextured, command_bytes);
            _ = draw_triangle_textured;
            //unreachable; // FIXME
        },
        .DrawQuadTexturedOpaqueBlended, .DrawQuadTexturedOpaque, .DrawQuadTexturedTransparentBlended, .DrawQuadTexturedTransparent => {
            const draw_quad_textured = std.mem.bytesAsValue(g0.DrawQuadTextured, command_bytes);
            _ = draw_quad_textured;
            //unreachable; // FIXME
        },
        .DrawTriangleShadedOpaque, .DrawTriangleShadedTransparent => {
            const draw_triangle_shaded = std.mem.bytesAsValue(g0.DrawTriangleShaded, command_bytes);
            _ = draw_triangle_shaded;
            //unreachable; // FIXME
        },
        .DrawQuadShadedOpaque, .DrawQuadShadedTransparent => {
            const draw_quad_shaded = std.mem.bytesAsValue(g0.DrawQuadShaded, command_bytes);
            _ = draw_quad_shaded;
            //unreachable; // FIXME
        },
        .CopyRectangleVRAMtoCPU => {
            const copy_rectangle = std.mem.bytesAsValue(g0.CopyRectangleAcrossCPU, command_bytes);
            std.debug.assert(copy_rectangle.zero_b0_23 == 0);

            // FIXME FIXME FIXME
            //unreachable; // FIXME
        },
        .CopyRectangleCPUtoVRAM => {
            const copy_rectangle = std.mem.bytesAsValue(g0.CopyRectangleAcrossCPU, command_bytes);

            std.debug.assert(copy_rectangle.extent_x > 0);
            std.debug.assert(copy_rectangle.extent_y > 0);

            psx.gpu.gp0_copy_mode = .{
                .command = copy_rectangle.*,
                .index_x = 0,
                .index_y = 0,
            };

            std.debug.assert(copy_rectangle.zero_b0_23 == 0);
        },
        .SetDrawMode => {
            const draw_mode = std.mem.bytesAsValue(g0.SetDrawMode, command_bytes);

            psx.mmio.gpu.GPUSTAT.texture_x_base = draw_mode.texture_x_base;
            psx.mmio.gpu.GPUSTAT.texture_y_base = draw_mode.texture_y_base;
            psx.mmio.gpu.GPUSTAT.semi_transparency = draw_mode.semi_transparency;
            psx.mmio.gpu.GPUSTAT.texture_page_colors = draw_mode.texture_page_colors;
            psx.mmio.gpu.GPUSTAT.dither_mode = draw_mode.dither_mode;
            psx.mmio.gpu.GPUSTAT.draw_to_display_area = draw_mode.draw_to_display_area;
            psx.mmio.gpu.GPUSTAT.texture_disable = draw_mode.texture_disable;

            psx.gpu.rectangle_texture_x_flip = draw_mode.rectangle_texture_x_flip;
            psx.gpu.rectangle_texture_y_flip = draw_mode.rectangle_texture_y_flip;

            std.debug.assert(draw_mode.texture_page_colors != .Reserved);
            std.debug.assert(draw_mode.zero_b14_23 == 0);
        },
        .SetTextureWindow => {
            const texture_window = std.mem.bytesAsValue(g0.SetTextureWindow, command_bytes);

            psx.gpu.texture_window_x_mask = texture_window.mask_x;
            psx.gpu.texture_window_y_mask = texture_window.mask_y;
            psx.gpu.texture_window_x_offset = texture_window.offset_x;
            psx.gpu.texture_window_y_offset = texture_window.offset_y;

            std.debug.assert(texture_window.zero_b20_23 == 0);
        },
        .SetDrawingAreaTopLeft => {
            const drawing_area = std.mem.bytesAsValue(g0.SetDrawingAreaTopLeft, command_bytes);

            psx.gpu.drawing_area_left = drawing_area.left;
            psx.gpu.drawing_area_top = drawing_area.top;

            std.debug.assert(drawing_area.zero_b20_23 == 0);
        },
        .SetDrawingAreaBottomRight => {
            const drawing_area = std.mem.bytesAsValue(g0.SetDrawingAreaBottomRight, command_bytes);

            psx.gpu.drawing_area_right = drawing_area.right;
            psx.gpu.drawing_area_bottom = drawing_area.bottom;

            std.debug.assert(drawing_area.zero_b20_23 == 0);
        },
        .SetDrawingOffset => {
            const drawing_offset = std.mem.bytesAsValue(g0.SetDrawingOffset, command_bytes);

            psx.gpu.drawing_x_offset = drawing_offset.x;
            psx.gpu.drawing_y_offset = drawing_offset.y;

            std.debug.assert(drawing_offset.zero_b22_23 == 0);
        },
        .SetMaskBitSetting => {
            const mask_bit_setting = std.mem.bytesAsValue(g0.SetMaskBitSetting, command_bytes);

            psx.mmio.gpu.GPUSTAT.set_mask_when_drawing = mask_bit_setting.set_mask_when_drawing;
            psx.mmio.gpu.GPUSTAT.check_mask_before_drawing = mask_bit_setting.check_mask_before_drawing;

            std.debug.assert(mask_bit_setting.zero_b2_23 == 0);
        },
        _ => unreachable,
    }
}

pub fn execute_gp1_command(psx: *PSXState, command_raw: g1.CommandRaw) void {
    if (config.enable_gpu_debug) {
        std.debug.print("GP1 COMMAND value: 0x{x:0>8}\n", .{@as(u32, @bitCast(command_raw))});
    }

    switch (g1.make_command(command_raw)) {
        .SoftReset => |soft_reset| {
            execute_reset(psx);

            std.debug.assert(soft_reset.zero_b0_23 == 0);
        },
        .CommandBufferReset => |command_buffer_reset| {
            execute_reset_command_buffer(psx);

            std.debug.assert(command_buffer_reset.zero_b0_23 == 0);
        },
        .AcknowledgeInterrupt => |acknowledge_interrupt| {
            std.debug.assert(acknowledge_interrupt.zero_b0_23 == 0);
            // FIXME
        },
        .SetDisplayEnabled => |display_enabled| {
            psx.mmio.gpu.GPUSTAT.display_enabled = display_enabled.display_enabled;

            std.debug.assert(display_enabled.zero_b1_23 == 0);
        },
        .SetDMADirection => |dma_direction| {
            psx.mmio.gpu.GPUSTAT.dma_direction = dma_direction.dma_direction;

            std.debug.assert(dma_direction.zero_b2_23 == 0);
        },
        .SetDisplayVRAMStart => |display_vram_start| {
            psx.gpu.display_vram_x_start = display_vram_start.x;
            psx.gpu.display_vram_y_start = display_vram_start.y;

            std.debug.assert(display_vram_start.zero_b19_23 == 0);
        },
        .SetDisplayHorizontalRange => |display_horizontal_range| {
            psx.gpu.display_horiz_start = display_horizontal_range.x1;
            psx.gpu.display_horiz_end = display_horizontal_range.x2;
        },
        .SetDisplayVerticalRange => |display_vertical_range| {
            psx.gpu.display_line_start = display_vertical_range.y1;
            psx.gpu.display_line_end = display_vertical_range.y2;

            std.debug.assert(display_vertical_range.zero_b20_23 == 0);
        },
        .SetDisplayMode => |display_mode| {
            psx.mmio.gpu.GPUSTAT.horizontal_resolution1 = display_mode.horizontal_resolution1;
            psx.mmio.gpu.GPUSTAT.vertical_resolution = display_mode.vertical_resolution;
            psx.mmio.gpu.GPUSTAT.video_mode = display_mode.video_mode;
            psx.mmio.gpu.GPUSTAT.display_area_color_depth = display_mode.display_area_color_depth;
            psx.mmio.gpu.GPUSTAT.vertical_interlace = display_mode.vertical_interlace;
            psx.mmio.gpu.GPUSTAT.horizontal_resolution2 = display_mode.horizontal_resolution2;
            psx.mmio.gpu.GPUSTAT.reverse_flag = display_mode.reverse_flag;

            std.debug.assert(display_mode.reverse_flag == 0);
            std.debug.assert(display_mode.zero_b8_23 == 0);
        },
        else => unreachable,
    }
}

fn execute_reset(psx: *PSXState) void {
    psx.gpu = .{};
    psx.mmio.gpu.GPUSTAT = .{};

    execute_reset_command_buffer(psx);
    // FIXME invalidate GPU cache
}

fn execute_reset_command_buffer(psx: *PSXState) void {
    psx.gpu.gp0_pending_command = null;
    psx.gpu.gp0_copy_mode = null;
    // FIXME clear command FIFO
}
