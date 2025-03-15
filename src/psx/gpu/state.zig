const std = @import("std");

const g0 = @import("instructions_g0.zig");

pub const GPUState = struct {
    texture_window_x_mask: u5 = 0,
    texture_window_y_mask: u5 = 0,
    texture_window_x_offset: u5 = 0,
    texture_window_y_offset: u5 = 0,

    rectangle_texture_x_flip: u1 = 0,
    rectangle_texture_y_flip: u1 = 0,

    drawing_area_left: u10 = 0,
    drawing_area_top: u10 = 0,
    drawing_area_right: u10 = 0,
    drawing_area_bottom: u10 = 0,

    drawing_x_offset: i11 = 0,
    drawing_y_offset: i11 = 0,

    display_vram_x_start: u16 = 0, // FIXME Type
    display_vram_y_start: u16 = 0, // FIXME Type

    display_horiz_start: u16 = 0x200, // FIXME Type
    display_horiz_end: u16 = 0xc00, // FIXME Type

    display_line_start: u16 = 0x10, // FIXME Type
    display_line_end: u16 = 0x100, // FIXME Type

    gp0_pending_bytes: [g0.MaxCommandSizeBytes]u8 = undefined,
    gp0_pending_command: ?struct {
        op_code: g0.OpCode,
        current_byte_index: usize,
        command_size_bytes: usize,
    } = null,

    gp0_copy_mode: ?struct {
        command: g0.CopyRectangleAcrossCPU,
        index_x: usize,
        index_y: usize,
    } = null,

    pending_draw: bool = false, // Signals that the frame is ready to be drawn

    frame_index: u64 = 0,

    vertex_offset: u32 = 0,
    vertex_buffer: []PhatVertex,

    index_offset: u32 = 0,
    index_buffer: []u32,

    draw_command_buffer: []DrawCommand,
    draw_command_offset: u32 = 0,
};

pub fn create_gpu_state(allocator: std.mem.Allocator) !GPUState {
    const vertex_buffer = try allocator.alloc(PhatVertex, 10000); // FIXME
    errdefer allocator.free(vertex_buffer);

    const index_buffer = try allocator.alloc(u32, 10000); // FIXME
    errdefer allocator.free(index_buffer);

    const draw_command_buffer = try allocator.alloc(DrawCommand, 10000); // FIXME
    errdefer allocator.free(draw_command_buffer);

    return GPUState{
        .vertex_buffer = vertex_buffer,
        .index_buffer = index_buffer,
        .draw_command_buffer = draw_command_buffer,
    };
}

pub fn destroy_gpu_state(state: *GPUState, allocator: std.mem.Allocator) void {
    allocator.free(state.vertex_buffer);
    allocator.free(state.index_buffer);
    allocator.free(state.draw_command_buffer);
}

pub const PhatVertex = struct {
    position: f32_3,
    color: f32_3,
};

pub const f32_2 = @Vector(2, f32);
pub const f32_3 = @Vector(3, f32);

pub const DrawCommand = struct {
    op_code: g0.OpCode,
    index_offset: u32,
    index_count: u32,
};
