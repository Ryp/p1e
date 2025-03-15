const std = @import("std");

const PSXState = @import("../state.zig").PSXState;
const state = @import("state.zig");
const f32_2 = state.f32_2;
const f32_3 = state.f32_3;
const PhatVertex = state.PhatVertex;
const DrawCommand = state.DrawCommand;

const g0 = @import("instructions_g0.zig");
const g1 = @import("instructions_g1.zig");

const config = @import("../config.zig");

// FIXME be very careful with endianness here
pub fn store_gp0_u32(psx: *PSXState, value: u32) void {
    if (config.enable_gpu_debug) {
        std.debug.print("GP0 write: 0x{x:0>8}\n", .{value});
    }

    if (psx.gpu.gp0_pending_command == null and psx.gpu.gp0_copy_mode == null) {
        const op_code: g0.OpCode = @bitCast(@as(u8, @intCast(value >> 24)));
        const command_size_bytes = g0.get_command_size_bytes(op_code); // This sucks

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

// FIXME normalization from viewport!
// FIMXE Third channel isn't really needed, or at least not at that time.
// FIXCME can we do float4(float2 , float2) in zig?
fn packed_vertex_to_f32_3(packed_vertex: g0.PackedVertexPos) f32_3 {
    return .{
        @floatFromInt(packed_vertex.x),
        @floatFromInt(packed_vertex.y),
        0.0,
    };
}

fn packed_color_to_f32_3(packed_vertex: g0.PackedColor) f32_3 {
    return f32_3{
        @floatFromInt(packed_vertex.r),
        @floatFromInt(packed_vertex.g),
        @floatFromInt(packed_vertex.b),
    } * @as(f32_3, @splat(1.0 / 255.0));
}

const PhatPackedVertex = struct {
    position: g0.PackedVertexPos,
    color: g0.PackedColor,
};

fn push_packed_triangle_color(psx: *PSXState, op_code: g0.OpCode, v1: PhatPackedVertex, v2: PhatPackedVertex, v3: PhatPackedVertex) void {
    const vertices = [3]PhatVertex{ .{
        .position = packed_vertex_to_f32_3(v1.position),
        .color = packed_color_to_f32_3(v1.color),
    }, .{
        .position = packed_vertex_to_f32_3(v2.position),
        .color = packed_color_to_f32_3(v2.color),
    }, .{
        .position = packed_vertex_to_f32_3(v3.position),
        .color = packed_color_to_f32_3(v3.color),
    } };

    const indices = [3]u32{
        psx.gpu.vertex_offset + 0,
        psx.gpu.vertex_offset + 1,
        psx.gpu.vertex_offset + 2,
    };

    psx.gpu.draw_command_buffer[psx.gpu.draw_command_offset] = .{
        .op_code = op_code,
        .index_offset = psx.gpu.index_offset,
        .index_count = indices.len,
    };

    @memcpy(psx.gpu.vertex_buffer[psx.gpu.vertex_offset..][0..vertices.len], &vertices);

    @memcpy(psx.gpu.index_buffer[psx.gpu.index_offset..][0..indices.len], &indices);

    // Update counters at the end
    psx.gpu.vertex_offset += vertices.len;
    psx.gpu.index_offset += indices.len;
    psx.gpu.draw_command_offset += 1;
}

fn push_packed_quad_color(psx: *PSXState, op_code: g0.OpCode, v1: PhatPackedVertex, v2: PhatPackedVertex, v3: PhatPackedVertex, v4: PhatPackedVertex) void {
    const vertices = [4]PhatVertex{ .{
        .position = packed_vertex_to_f32_3(v1.position),
        .color = packed_color_to_f32_3(v1.color),
    }, .{
        .position = packed_vertex_to_f32_3(v2.position),
        .color = packed_color_to_f32_3(v2.color),
    }, .{
        .position = packed_vertex_to_f32_3(v3.position),
        .color = packed_color_to_f32_3(v3.color),
    }, .{
        .position = packed_vertex_to_f32_3(v4.position),
        .color = packed_color_to_f32_3(v4.color),
    } };

    const indices = [6]u32{
        psx.gpu.vertex_offset + 0, // 1st triangle
        psx.gpu.vertex_offset + 1,
        psx.gpu.vertex_offset + 2,
        psx.gpu.vertex_offset + 1, // 2nd triangle
        psx.gpu.vertex_offset + 2,
        psx.gpu.vertex_offset + 3,
    };

    psx.gpu.draw_command_buffer[psx.gpu.draw_command_offset] = .{
        .op_code = op_code,
        .index_offset = psx.gpu.index_offset,
        .index_count = indices.len,
    };

    @memcpy(psx.gpu.vertex_buffer[psx.gpu.vertex_offset..][0..vertices.len], &vertices);

    @memcpy(psx.gpu.index_buffer[psx.gpu.index_offset..][0..indices.len], &indices);

    // Update counters at the end
    psx.gpu.vertex_offset += vertices.len;
    psx.gpu.index_offset += indices.len;
    psx.gpu.draw_command_offset += 1;
}

fn execute_gp0_command(psx: *PSXState, op_code: g0.OpCode, command_bytes: []u8) void {
    switch (op_code.primary) {
        .Special => {
            switch (op_code.secondary.special) {
                .ClearCache => {
                    const clear_texture_cache = std.mem.bytesAsValue(g0.ClearTextureCache, command_bytes);
                    std.debug.assert(clear_texture_cache.zero_b0_23 == 0);

                    // unreachable;
                    // FIXME TO IMPLEMENT
                },
                .FillRectangleInVRAM => {
                    unreachable; // FIXME
                },
                .Unknown => {
                    unreachable; // FIXME
                },
                .InterrupRequest => {
                    unreachable; // FIXME
                },
                _ => {
                    // Probably a noop => Do nothing!
                },
            }
        },
        .DrawPoly => {
            std.debug.assert(!psx.gpu.pending_draw);

            const draw_poly = op_code.secondary.draw_poly;
            if (draw_poly.is_shaded) {
                if (draw_poly.is_textured) {
                    if (draw_poly.is_quad) {
                        // FIXME!!!!!!
                        const quad_shaded_textured = std.mem.bytesAsValue(g0.DrawQuadShadedTextured, command_bytes);

                        push_packed_quad_color(psx, op_code, .{
                            .position = quad_shaded_textured.v1_pos,
                            .color = quad_shaded_textured.v1_color,
                        }, .{
                            .position = quad_shaded_textured.v2_pos,
                            .color = quad_shaded_textured.v2_color,
                        }, .{
                            .position = quad_shaded_textured.v3_pos,
                            .color = quad_shaded_textured.v3_color,
                        }, .{
                            .position = quad_shaded_textured.v4_pos,
                            .color = quad_shaded_textured.v4_color,
                        });
                    } else {
                        // FIXME!!!!!!
                        const tri_shaded_textured = std.mem.bytesAsValue(g0.DrawTriangleShadedTextured, command_bytes);

                        push_packed_triangle_color(psx, op_code, .{
                            .position = tri_shaded_textured.v1_pos,
                            .color = tri_shaded_textured.v1_color,
                        }, .{
                            .position = tri_shaded_textured.v2_pos,
                            .color = tri_shaded_textured.v2_color,
                        }, .{
                            .position = tri_shaded_textured.v3_pos,
                            .color = tri_shaded_textured.v3_color,
                        });
                    }
                } else {
                    if (draw_poly.is_quad) {
                        const quad_shaded = std.mem.bytesAsValue(g0.DrawQuadShaded, command_bytes);

                        push_packed_quad_color(psx, op_code, .{
                            .position = quad_shaded.v1_pos,
                            .color = quad_shaded.v1_color,
                        }, .{
                            .position = quad_shaded.v2_pos,
                            .color = quad_shaded.v2_color,
                        }, .{
                            .position = quad_shaded.v3_pos,
                            .color = quad_shaded.v3_color,
                        }, .{
                            .position = quad_shaded.v4_pos,
                            .color = quad_shaded.v4_color,
                        });
                    } else {
                        const triangle_shaded = std.mem.bytesAsValue(g0.DrawTriangleShaded, command_bytes);

                        push_packed_triangle_color(psx, op_code, .{
                            .position = triangle_shaded.v1_pos,
                            .color = triangle_shaded.v1_color,
                        }, .{
                            .position = triangle_shaded.v2_pos,
                            .color = triangle_shaded.v2_color,
                        }, .{
                            .position = triangle_shaded.v3_pos,
                            .color = triangle_shaded.v3_color,
                        });
                    }
                }
            } else {
                if (draw_poly.is_textured) {
                    if (draw_poly.is_quad) {
                        // FIXMEEEEEEEEEEE
                        const quad_textured = std.mem.bytesAsValue(g0.DrawQuadTextured, command_bytes);

                        push_packed_quad_color(psx, op_code, .{
                            .position = quad_textured.v1_pos,
                            .color = quad_textured.color,
                        }, .{
                            .position = quad_textured.v2_pos,
                            .color = quad_textured.color,
                        }, .{
                            .position = quad_textured.v3_pos,
                            .color = quad_textured.color,
                        }, .{
                            .position = quad_textured.v4_pos,
                            .color = quad_textured.color,
                        });
                    } else {
                        // FIXMEEEEEEEEEEE
                        const triangle_textured = std.mem.bytesAsValue(g0.DrawTriangleTextured, command_bytes);

                        push_packed_triangle_color(psx, op_code, .{
                            .position = triangle_textured.v1_pos,
                            .color = triangle_textured.color,
                        }, .{
                            .position = triangle_textured.v2_pos,
                            .color = triangle_textured.color,
                        }, .{
                            .position = triangle_textured.v3_pos,
                            .color = triangle_textured.color,
                        });
                    }
                } else {
                    if (draw_poly.is_quad) {
                        const quad_monochrome = std.mem.bytesAsValue(g0.DrawQuadMonochrome, command_bytes);

                        push_packed_quad_color(psx, op_code, .{
                            .position = quad_monochrome.v1_pos,
                            .color = quad_monochrome.color,
                        }, .{
                            .position = quad_monochrome.v2_pos,
                            .color = quad_monochrome.color,
                        }, .{
                            .position = quad_monochrome.v3_pos,
                            .color = quad_monochrome.color,
                        }, .{
                            .position = quad_monochrome.v4_pos,
                            .color = quad_monochrome.color,
                        });
                    } else {
                        const triangle_monochrome = std.mem.bytesAsValue(g0.DrawTriangleMonochrome, command_bytes);

                        push_packed_triangle_color(psx, op_code, .{
                            .position = triangle_monochrome.v1_pos,
                            .color = triangle_monochrome.color,
                        }, .{
                            .position = triangle_monochrome.v2_pos,
                            .color = triangle_monochrome.color,
                        }, .{
                            .position = triangle_monochrome.v3_pos,
                            .color = triangle_monochrome.color,
                        });
                    }
                }
            }
        },
        .DrawLine => {
            std.debug.assert(!psx.gpu.pending_draw);
            unreachable;
        },
        .DrawRect => {
            std.debug.assert(!psx.gpu.pending_draw);
            unreachable;
        },
        .CopyRectangleVRAMtoVRAM => {
            unreachable;
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
        .CopyRectangleVRAMtoCPU => {
            const copy_rectangle = std.mem.bytesAsValue(g0.CopyRectangleAcrossCPU, command_bytes);
            std.debug.assert(copy_rectangle.zero_b0_23 == 0);
        },
        .DrawModifier => {
            switch (op_code.secondary.modifier) {
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

                    std.debug.print("Frame {} end: vertex = {}, draw commands = {}\n", .{ psx.gpu.frame_index, psx.gpu.vertex_offset, psx.gpu.draw_command_offset });

                    // FIXME reset frame data!
                    if (!psx.headless) {
                        psx.gpu.pending_draw = true;
                    }
                },
                .SetMaskBitSetting => {
                    const mask_bit_setting = std.mem.bytesAsValue(g0.SetMaskBitSetting, command_bytes);

                    psx.mmio.gpu.GPUSTAT.set_mask_when_drawing = mask_bit_setting.set_mask_when_drawing;
                    psx.mmio.gpu.GPUSTAT.check_mask_before_drawing = mask_bit_setting.check_mask_before_drawing;

                    std.debug.assert(mask_bit_setting.zero_b2_23 == 0);
                },
                _ => unreachable,
            }
        },
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

// FIXME public API
pub fn consume_pending_draw(psx: *PSXState) void {
    std.debug.assert(!psx.headless);

    psx.gpu.pending_draw = false;

    psx.gpu.frame_index += 1;
    reset_frame_data(psx);
}

fn execute_reset(psx: *PSXState) void {
    psx.gpu = .{
        .vertex_buffer = psx.gpu.vertex_buffer,
        .index_buffer = psx.gpu.index_buffer,
        .draw_command_buffer = psx.gpu.draw_command_buffer,
    };
    psx.mmio.gpu.GPUSTAT = .{};

    execute_reset_command_buffer(psx);
    // FIXME invalidate GPU cache
}

fn execute_reset_command_buffer(psx: *PSXState) void {
    psx.gpu.gp0_pending_command = null;
    psx.gpu.gp0_copy_mode = null;
    // FIXME clear command FIFO

    reset_frame_data(psx);
}

// Internal draw command buffer reset
fn reset_frame_data(psx: *PSXState) void {
    psx.gpu.vertex_offset = 0;
    psx.gpu.index_offset = 0;
    psx.gpu.draw_command_offset = 0;
}
