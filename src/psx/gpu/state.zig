const std = @import("std");

const g0 = @import("instructions_g0.zig");

pub const GPUState = struct {
    vram: []u8,

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

    gp_read_data: u32 = 0, // FIXME

    pending_draw: bool = false, // Signals that the frame is ready to be drawn

    frame_index: u64 = 0,

    vertex_offset: u32 = 0,
    vertex_buffer: []PhatVertex,

    index_offset: u32 = 0,
    index_buffer: []u32,

    draw_command_buffer: []DrawCommand,
    draw_command_offset: u32 = 0,

    // FIXME
    pub fn write(self: @This(), writer: anytype) !void {
        try writer.writeAll(self.vram);
    }

    // FIXME
    pub fn read(self: *@This(), reader: anytype) !void {
        const vram_bytes_written = try reader.readAll(self.vram);
        if (vram_bytes_written != self.vram.len) {
            return error.InvalidVRAMSize;
        }
    }
};

pub fn create_gpu_state(allocator: std.mem.Allocator) !GPUState {
    const vram = try allocator.alloc(u8, VRAM_SizeBytes);
    errdefer allocator.free(vram);

    const vertex_buffer = try allocator.alloc(PhatVertex, 1_000_000); // FIXME
    errdefer allocator.free(vertex_buffer);

    const index_buffer = try allocator.alloc(u32, 1_000_000); // FIXME
    errdefer allocator.free(index_buffer);

    const draw_command_buffer = try allocator.alloc(DrawCommand, 1_000_000); // FIXME
    errdefer allocator.free(draw_command_buffer);

    return GPUState{
        .vram = vram,
        .vertex_buffer = vertex_buffer,
        .index_buffer = index_buffer,
        .draw_command_buffer = draw_command_buffer,
    };
}

pub fn destroy_gpu_state(state: *GPUState, allocator: std.mem.Allocator) void {
    allocator.free(state.vram);
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

// Summary of GPU Differences
//
//   Differences...                Old 160pin GPU          New 208pin GPU
//   GPU Chip                      CXD8514Q                CXD8561Q/BQ/CQ/CXD9500Q
//   Mainboard                     EARLY-PU-8 and below    LATE-PU-8 and up
//   Memory Type                   Dual-ported VRAM        Normal DRAM
//   GPUSTAT.13 when interlace=off always 0                always 1
//   GPUSTAT.14                    always 0                reverseflag
//   GPUSTAT.15                    always 0                texture_disable
//   GP1(10h:index3..4)            19bit (1MB VRAM)        20bit (2MB VRAM)
//   GP1(10h:index7)               N/A                     00000002h version
//   GP1(10h:index8)               mirror of index0        00000000h zero
//   GP1(10h:index9..F)            mirror of index1..7     N/A
//   GP1(20h)                      whatever? used for detecting old gpu
//   GP0(E1h).bit12/13             without x/y-flip        with x/y-flip
//   GP0(03h)                      N/A (no stored in fifo) unknown/unused command
//   Shaded Textures               ((color/8)*texel)/2     (color*texel)/16
//   GP0(02h) FillVram             xpos.bit0-3=0Fh=bugged  xpos.bit0-3=ignored
//   dma-to-vram: doesn't work with blksiz>10h (new gpu works with blksiz=8C0h!)
//   dma-to-vram: MAYBE also needs extra software-handshake to confirm DMA done?
//    320*224 pix = 11800h pix = 8C00h words
//   GP0(80h) VramToVram           works                   Freeze on large moves?
pub const GPUType = 0x00_00_00_02;
const VRAM_SizeBytes = 1024 * 1024; // 1 MiB
