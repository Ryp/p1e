const std = @import("std");

const PSXState = @import("../state.zig").PSXState;
const state = @import("state.zig");
const f32_2 = state.f32_2;
const f32_3 = state.f32_3;
const DrawCommand = state.DrawCommand;

const g0 = @import("instructions_g0.zig");
const g1 = @import("instructions_g1.zig");
const vram = @import("vram.zig");

const pixel_format = @import("pixel_format.zig");
const PackedRGB8 = pixel_format.PackedRGB8;
const PackedRGB5A1 = pixel_format.PackedRGB5A1;

const draw_line = @import("draw_line.zig");
const draw_poly = @import("draw_poly.zig");
const draw_rect = @import("draw_rect.zig");

const config = @import("../config.zig");
const cpu_execution = @import("../cpu/execution.zig");
const timings = @import("../timings.zig");

// FIXME Assumes ticks is never bigger than the vblank interval
pub fn execute_ticks(psx: *PSXState, ticks: u32) void {
    if (psx.gpu.pending_vblank_ticks > ticks) {
        psx.gpu.pending_vblank_ticks -= ticks;
    } else {
        psx.gpu.pending_vblank_ticks += @as(u32, switch (psx.mmio.gpu.GPUSTAT.video_mode) {
            .NTSC => timings.VBlankTicksNTSC,
            .PAL => timings.VBlankTicksPAL,
        }) - ticks;

        cpu_execution.request_hardware_interrupt(psx, .IRQ0_VBlank);

        if (psx.mmio.gpu.GPUSTAT.vertical_interlace) {
            switch (psx.mmio.gpu.GPUSTAT.vertical_resolution) {
                ._240lines => {
                    // FIXME handle field switching properly
                    psx.mmio.gpu.GPUSTAT.drawing_even_odd_line_in_interlace_mode = 0;
                },
                ._480lines => {
                    psx.mmio.gpu.GPUSTAT.drawing_even_odd_line_in_interlace_mode ^= 1;
                },
            }
        } else {
            psx.mmio.gpu.GPUSTAT.drawing_even_odd_line_in_interlace_mode = 0;
        }

        // FIXME reset frame data!
        if (!psx.headless) {
            psx.gpu.backend.pending_draw = true;
        }
    }
}

// FIXME be very careful with endianness here
pub fn load_gpuread_u32(psx: *PSXState) u32 {
    std.debug.assert(psx.mmio.gpu.GPUREAD.zero == 0);

    switch (psx.gpu.gpuread_mode) {
        .idle => {
            // Let it return the last value
            if (config.enable_gpu_debug) {
                std.debug.print("WARNING: GPUREAD in idle mode!\n", .{});
            }
        },
        .gpu_attributes => {
            // gpuread_last_value should already contain the right value by this point
            psx.gpu.gpuread_mode = .idle;
        },
        .copy_rect_vram_to_cpu => |*copy_mode| {
            // FIXME handle mask settings
            std.debug.assert(copy_mode.command.op_code.primary == .CopyRectangleVRAMtoCPU);

            var dst_pixels: [2]PackedRGB5A1 = undefined;

            for (&dst_pixels) |*dst_pixel| {
                const texel_offset = vram.flat_texel_offset(copy_mode.command.position_top_left.x + copy_mode.index_x, copy_mode.command.position_top_left.y + copy_mode.index_y);

                dst_pixel.* = psx.gpu.vram_texels[texel_offset];

                copy_mode.index_x += 1;

                if (copy_mode.index_x == copy_mode.command.size.x) {
                    copy_mode.index_x = 0;
                    copy_mode.index_y += 1;
                }

                // Check for end condition
                if (copy_mode.index_y == copy_mode.command.size.y) {
                    psx.gpu.gpuread_mode = .idle;
                    break;
                }
            }

            const dst_bytes = std.mem.asBytes(&dst_pixels);
            psx.gpu.gpuread_last_value = std.mem.bytesAsValue(u32, dst_bytes).*;
        },
    }

    return psx.gpu.gpuread_last_value;
}

// FIXME be very careful with endianness here
// NOTE: This function makes use of zig labeled switch
pub fn store_gp0_u32(psx: *PSXState, value: u32) void {
    if (config.enable_gpu_debug) {
        std.debug.print("GP0 write: 0x{x:0>8}\n", .{value});
    }

    main_switch: switch (psx.gpu.gp0_write_mode) {
        .idle => {
            const op_code: g0.OpCode = @bitCast(@as(u8, @intCast(value >> 24)));
            const command_size_bytes = g0.get_command_size_bytes(op_code); // This sucks

            psx.gpu.gp0_write_mode = .{ .waiting_for_command_bytes = .{
                .op_code = op_code,
                .current_byte_index = 0,
                .command_size_bytes = command_size_bytes,
            } };

            continue :main_switch psx.gpu.gp0_write_mode;
        },
        .waiting_for_command_bytes => |*pending_command| {
            // Write current u32 to the pending command buffer
            std.mem.writeInt(u32, pending_command.bytes[pending_command.current_byte_index..][0..4], value, .little);

            pending_command.current_byte_index += @sizeOf(u32);

            // Check if we wrote enough bytes to dispatch a command
            if (pending_command.current_byte_index == pending_command.command_size_bytes) {
                const command_bytes = pending_command.bytes[0..pending_command.command_size_bytes];

                psx.gpu.gp0_write_mode = execute_gp0_command(psx, pending_command.op_code, command_bytes);
            }
        },
        .copy_rect_cpu_to_vram => |*copy_mode| {
            // FIXME handle mask settings
            std.debug.assert(copy_mode.command.op_code.primary == .CopyRectangleCPUtoVRAM);

            const src_pixels = std.mem.bytesAsSlice(PackedRGB5A1, std.mem.asBytes(&value));

            std.debug.assert(src_pixels.len == 2);

            for (src_pixels) |src_pixel| {
                const texel_offset = vram.flat_texel_offset(copy_mode.command.position_top_left.x + copy_mode.index_x, copy_mode.command.position_top_left.y + copy_mode.index_y);

                psx.gpu.vram_texels[texel_offset] = src_pixel;

                copy_mode.index_x += 1;

                if (copy_mode.index_x == copy_mode.command.size.x) {
                    copy_mode.index_x = 0;
                    copy_mode.index_y += 1;
                }

                // Check for end condition
                if (copy_mode.index_y == copy_mode.command.size.y) {
                    psx.gpu.gp0_write_mode = .idle;
                    break;
                }
            }
        },
    }
}

// Care with the return value, we update gp0_write_mode accordingly
fn execute_gp0_command(psx: *PSXState, op_code: g0.OpCode, command_bytes: []const u8) state.GP0WriteMode {
    if (config.enable_gpu_debug) {
        std.debug.print("Execute GP0 command 0x{x:0<2} = {any}\n", .{ @as(u8, @bitCast(op_code)), op_code });
    }

    return switch (op_code.primary) {
        .Special => {
            switch (op_code.secondary.special) {
                .Nop => {
                    // This command doesn't take up space in the FIFO (eg. even if a VRAM-to-VRAM transfer is still busy, one can send dozens of GP0(00h) commands, without the command FIFO becoming full. So, either the command is ignored (or, if it has a function, it is executed immediately, even while the transfer is busy).
                    // ...
                    // GP0(00h) unknown, used with parameter = 08A16Ch... or rather 08FDBCh ... the written value seems to be a bios/ram memory address, anded with 00FFFFFFh... maybe a bios bug?
                    // GP0(00h) seems to be often inserted between Texpage and Rectangle commands, maybe it acts as a NOP, which may be required between that commands, for timing reasons...?
                },
                .ClearCache => {
                    const clear_texture_cache = std.mem.bytesAsValue(g0.ClearTextureCache, command_bytes);
                    std.debug.assert(clear_texture_cache.zero_b0_23 == 0);

                    // FIXME Implement

                    if (config.enable_gpu_debug) {
                        std.debug.print("Clear texture cache command ignored\n", .{});
                    }
                },
                .FillRectangleInVRAM => {
                    const fill_rectangle = std.mem.bytesAsValue(g0.FillRectangleInVRAM, command_bytes).*;
                    fill_rectangle_vram(psx, fill_rectangle);
                },
                .Unknown => {
                    @panic("Unknown!");
                },
                .InterruptRequest => {
                    psx.mmio.gpu.GPUSTAT.interrupt_request = 1;

                    cpu_execution.request_hardware_interrupt(psx, .IRQ1_GPU);
                },
                _ => {
                    // Probably a noop => Do nothing!
                    @panic("Just in case we're missing something");
                },
            }

            return .idle;
        },
        .DrawPoly => {
            std.debug.assert(!psx.gpu.backend.pending_draw);

            draw_poly.execute(psx, op_code.secondary.draw_poly, command_bytes);

            return .idle;
        },
        .DrawLine => {
            std.debug.assert(!psx.gpu.backend.pending_draw);

            draw_line.execute(psx, op_code.secondary.draw_line, command_bytes);

            return .idle;
        },
        .DrawRect => {
            std.debug.assert(!psx.gpu.backend.pending_draw);

            draw_rect.execute(psx, op_code.secondary.draw_rect, command_bytes);

            return .idle;
        },
        .CopyRectangleVRAMtoVRAM => {
            const copy_rectangle = std.mem.bytesAsValue(g0.CopyRectangleInVRAM, command_bytes).*;
            copy_rectangle_vram(psx, copy_rectangle);

            return .idle;
        },
        .CopyRectangleCPUtoVRAM, .CopyRectangleVRAMtoCPU => {
            const copy_rectangle = std.mem.bytesAsValue(g0.CopyRectangleAcrossCPU, command_bytes);

            std.debug.assert(copy_rectangle.size.x > 0);
            std.debug.assert(copy_rectangle.size.y > 0);

            const copy_mode = state.CopyMode{
                .command = copy_rectangle.*,
                .index_x = 0,
                .index_y = 0,
            };

            std.debug.assert(copy_rectangle.zero_b0_23 == 0);

            if (op_code.primary == .CopyRectangleCPUtoVRAM) {
                return .{ .copy_rect_cpu_to_vram = copy_mode };
            } else {
                std.debug.assert(psx.gpu.gpuread_mode == .idle);
                psx.gpu.gpuread_mode = .{ .copy_rect_vram_to_cpu = copy_mode };
                return .idle;
            }
        },
        .DrawModifier => {
            switch (op_code.secondary.modifier) {
                .SetDrawMode => {
                    const draw_mode = std.mem.bytesAsValue(g0.SetDrawMode, command_bytes);

                    psx.mmio.gpu.GPUSTAT.texture_x_base = draw_mode.texture_x_base;
                    psx.mmio.gpu.GPUSTAT.texture_y_base = draw_mode.texture_y_base;
                    psx.mmio.gpu.GPUSTAT.semi_transparency_mode = draw_mode.semi_transparency_mode;
                    psx.mmio.gpu.GPUSTAT.texture_page_colors = draw_mode.texture_page_colors;
                    psx.mmio.gpu.GPUSTAT.dither_mode = draw_mode.dither_mode;
                    psx.mmio.gpu.GPUSTAT.draw_to_display_area = draw_mode.draw_to_display_area;
                    psx.mmio.gpu.GPUSTAT.texture_disable = draw_mode.texture_disable;

                    psx.gpu.regs.rectangle_texture_x_flip = draw_mode.rectangle_texture_x_flip;
                    psx.gpu.regs.rectangle_texture_y_flip = draw_mode.rectangle_texture_y_flip;

                    std.debug.assert(draw_mode.zero_b14_23 == 0);
                },
                .SetTextureWindow => {
                    const texture_window = std.mem.bytesAsValue(g0.SetTextureWindow, command_bytes);

                    psx.gpu.regs.texture_window_x_mask = texture_window.mask_x << 3;
                    psx.gpu.regs.texture_window_y_mask = texture_window.mask_y << 3;
                    psx.gpu.regs.texture_window_x_offset = texture_window.offset_x << 3;
                    psx.gpu.regs.texture_window_y_offset = texture_window.offset_y << 3;

                    std.debug.assert(texture_window.zero_b20_23 == 0);
                },
                .SetDrawingAreaTopLeft => {
                    const drawing_area = std.mem.bytesAsValue(g0.SetDrawingAreaTopLeft, command_bytes);

                    psx.gpu.regs.drawing_area_left = drawing_area.left;
                    psx.gpu.regs.drawing_area_top = drawing_area.top;

                    // std.debug.assert(drawing_area.zero_b20_23 == 0);
                },
                .SetDrawingAreaBottomRight => {
                    const drawing_area = std.mem.bytesAsValue(g0.SetDrawingAreaBottomRight, command_bytes);

                    // Values are inclusive, so let's just offset them here to make life easier
                    psx.gpu.regs.drawing_area_right = @as(u32, drawing_area.right) + 1;
                    psx.gpu.regs.drawing_area_bottom = @as(u32, drawing_area.bottom) + 1;

                    // std.debug.assert(drawing_area.zero_b20_23 == 0);
                },
                .SetDrawingOffset => {
                    const drawing_offset = std.mem.bytesAsValue(g0.SetDrawingOffset, command_bytes);

                    psx.gpu.regs.drawing_x_offset = drawing_offset.x;
                    psx.gpu.regs.drawing_y_offset = drawing_offset.y;

                    std.debug.assert(drawing_offset.zero_b22_23 == 0);
                },
                .SetMaskBitSetting => {
                    const mask_bit_setting = std.mem.bytesAsValue(g0.SetMaskBitSetting, command_bytes);

                    psx.mmio.gpu.GPUSTAT.set_mask_when_drawing = mask_bit_setting.set_mask_when_drawing;
                    psx.mmio.gpu.GPUSTAT.check_mask_before_drawing = mask_bit_setting.check_mask_before_drawing;

                    std.debug.assert(mask_bit_setting.zero_b2_23 == 0);
                },
                _ => {
                    // Probably a noop => Do nothing!
                },
            }

            return .idle;
        },
    };
}

pub fn execute_gp1_command(psx: *PSXState, command_raw: g1.CommandRaw) void {
    if (config.enable_gpu_debug) {
        std.debug.print("GP1 COMMAND value: 0x{x:0>8}\n", .{@as(u32, @bitCast(command_raw))});
    }

    std.debug.assert(command_raw.unused_b22_23 == 0); // Technically could be anything

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

            psx.mmio.gpu.GPUSTAT.interrupt_request = 0;
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
            psx.gpu.regs.display_vram_x_start = display_vram_start.x;
            psx.gpu.regs.display_vram_y_start = display_vram_start.y;

            std.debug.assert(display_vram_start.zero_b19_23 == 0);
        },
        .SetDisplayHorizontalRange => |display_horizontal_range| {
            psx.gpu.regs.display_horiz_start = display_horizontal_range.x1;
            psx.gpu.regs.display_horiz_end = display_horizontal_range.x2;
        },
        .SetDisplayVerticalRange => |display_vertical_range| {
            psx.gpu.regs.display_line_start = display_vertical_range.y1;
            psx.gpu.regs.display_line_end = display_vertical_range.y2;

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

            std.debug.assert(psx.mmio.gpu.GPUSTAT.display_area_color_depth == ._15bits);

            std.debug.assert(display_mode.reverse_flag == 0);
            std.debug.assert(display_mode.zero_b8_23 == 0);
        },
        .TextureDisableNew => |texture_disable_new| {
            _ = texture_disable_new;
            @panic("Unimplemented");
        },
        .GetGPUInfo => |get_gpu_info| {
            std.debug.assert(get_gpu_info.unused_b4_23 == 0); // Technically could be anything

            execute_get_gpu_info(psx, get_gpu_info.op_code);
        },
        .UnknownCrash => @panic("GP1 UnknownCrash command executed!"),
        .TextureDisableOld => |texture_disable_old| {
            std.debug.assert(texture_disable_old.unknown_b0_23 == .Enable or texture_disable_old.unknown_b0_23 == .Disable);
            @panic("Unimplemented");
        },
    }
}

// FIXME public API
pub fn consume_pending_draw(psx: *PSXState) void {
    std.debug.assert(!psx.headless);

    psx.gpu.backend.pending_draw = false;
    psx.gpu.backend.frame_index += 1;

    reset_frame_data(psx);
}

fn execute_reset(psx: *PSXState) void {
    psx.gpu = .{
        .vram_texels = psx.gpu.vram_texels,
        .backend = .{
            .vertex_buffer = psx.gpu.backend.vertex_buffer,
            .index_buffer = psx.gpu.backend.index_buffer,
            .draw_command_buffer = psx.gpu.backend.draw_command_buffer,
        },
    };
    psx.mmio.gpu.GPUSTAT = .{};

    execute_reset_command_buffer(psx);
    // FIXME invalidate GPU cache
}

fn execute_reset_command_buffer(psx: *PSXState) void {
    psx.gpu.gp0_write_mode = .idle;
    psx.gpu.gpuread_mode = .idle;
    psx.gpu.gpuread_last_value = 0;

    // FIXME clear command FIFO

    reset_frame_data(psx);
}

// Internal draw command buffer reset
fn reset_frame_data(psx: *PSXState) void {
    psx.gpu.backend.vertex_offset = 0;
    psx.gpu.backend.index_offset = 0;
    psx.gpu.backend.draw_command_offset = 0;
}

fn copy_rectangle_vram(psx: *PSXState, copy_rectangle: g0.CopyRectangleInVRAM) void {
    std.debug.print("CopyRectangleInVRAM: {}\n", .{copy_rectangle});

    // FIXME handle mask settings
    // FIXME assumed no overlap, but maybe that's supported?
    // FIXME Wrapping maybe supported, we don't! Normally runtime checks raise those issues. Have faith.
    //std.debug.assert(fill_rectangle.position_top_left.x % 0x10 == 0);
    //std.debug.assert(fill_rectangle.size.x % 0x10 == 0);

    for (0..copy_rectangle.size.y) |y| {
        const offset_src_y = (copy_rectangle.position_top_left_src.y + y) * vram.TexelStrideY;
        const offset_dst_y = (copy_rectangle.position_top_left_dst.y + y) * vram.TexelStrideY;

        const vram_line_src = psx.gpu.vram_texels[offset_src_y .. offset_src_y + vram.TexelStrideY];
        const vram_line_dst = psx.gpu.vram_texels[offset_dst_y .. offset_dst_y + vram.TexelStrideY];

        const offset_src_x = copy_rectangle.position_top_left_src.x;
        const offset_dst_x = copy_rectangle.position_top_left_dst.x;

        const vram_src = vram_line_src[offset_src_x .. offset_src_x + copy_rectangle.size.x];
        const vram_dst = vram_line_dst[offset_dst_x .. offset_dst_x + copy_rectangle.size.x];

        @memcpy(vram_dst, vram_src);
    }
}

fn fill_rectangle_vram(psx: *PSXState, fill_rectangle: g0.FillRectangleInVRAM) void {
    if (config.enable_gpu_debug) {
        std.debug.print("FillRectangleInVRAM: {}\n", .{fill_rectangle});
    }

    // FIXME Wrapping is supported, we don't! Normally runtime checks raise those issues. Have faith.
    //std.debug.assert(fill_rectangle.position_top_left.x % 0x10 == 0);
    //std.debug.assert(fill_rectangle.size.x % 0x10 == 0);
    const interlaced_rendering_enabled = psx.mmio.gpu.GPUSTAT.vertical_interlace and psx.mmio.gpu.GPUSTAT.vertical_resolution == ._240lines and psx.mmio.gpu.GPUSTAT.draw_to_display_area == .Allowed;
    std.debug.assert(!interlaced_rendering_enabled);

    const fill_color_rgb5 = pixel_format.convert_rgb8_to_rgb5a1(fill_rectangle.color, 0);

    for (0..fill_rectangle.size.y) |y| {
        const offset_y = (fill_rectangle.position_top_left.y + y) * vram.TexelStrideY;

        const vram_type_line = psx.gpu.vram_texels[offset_y .. offset_y + vram.TexelStrideY];

        const offset_x = fill_rectangle.position_top_left.x;
        const vram_type_line_rect = vram_type_line[offset_x .. offset_x + fill_rectangle.size.x];

        @memset(vram_type_line_rect, fill_color_rgb5);
    }
}

fn execute_get_gpu_info(psx: *PSXState, op_code: g1.GPUInfoOpCode) void {
    const u32_4_u5 = packed struct(u32) {
        a_x: u5,
        a_y: u5,
        b_x: u5,
        b_y: u5,
        zero_b20_31: u12 = 0,
    };

    const u32_2_u10 = packed struct(u32) {
        x: u10,
        y: u10,
        zero_b20_31: u12 = 0,
    };

    const u32_2_i11 = packed struct(u32) {
        x: i11,
        y: i11,
        zero_b22_31: u10 = 0,
    };

    switch (op_code) {
        .TextureWindowSetting => {
            psx.gpu.gpuread_last_value = @bitCast(u32_4_u5{
                .a_x = @intCast(psx.gpu.regs.texture_window_x_mask >> 3),
                .a_y = @intCast(psx.gpu.regs.texture_window_y_mask >> 3),
                .b_x = @intCast(psx.gpu.regs.texture_window_x_offset >> 3),
                .b_y = @intCast(psx.gpu.regs.texture_window_y_offset >> 3),
            });
        },
        .DrawAreaTopLeft => {
            psx.gpu.gpuread_last_value = @bitCast(u32_2_u10{
                .x = @intCast(psx.gpu.regs.drawing_area_top),
                .y = @intCast(psx.gpu.regs.drawing_area_left),
            });
        },
        .DrawAreaBottomRight => {
            psx.gpu.gpuread_last_value = @bitCast(u32_2_u10{
                .x = @intCast(psx.gpu.regs.drawing_area_bottom - 1), // Exclusive to inclusive
                .y = @intCast(psx.gpu.regs.drawing_area_right - 1),
            });
        },
        .DrawOffset => {
            psx.gpu.gpuread_last_value = @bitCast(u32_2_i11{
                .x = psx.gpu.regs.drawing_x_offset,
                .y = psx.gpu.regs.drawing_y_offset,
            });
        },
        .GPUType => {
            psx.gpu.gpuread_last_value = state.GPUType;
        },
        .Unknown => {
            psx.gpu.gpuread_last_value = 0;
        },
        _ => {
            return; // Nop, do nothing and not even update mode!
        },
    }

    psx.gpu.gpuread_mode = .gpu_attributes;
}
