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

    frame_index: u64 = 0,

    vertex_offset: u32 = 0,
    triangle_offset: u32 = 0,
};
