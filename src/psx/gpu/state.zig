const std = @import("std");

const g0 = @import("instructions_g0.zig");
const pixel_format = @import("pixel_format.zig");
const vram = @import("vram.zig");

pub const GPUState = struct {
    vram_texels: []pixel_format.PackedRGB5A1,

    regs: packed struct { // FIXME packed because it's simple to serialize
        // NOTE:window settings are converted to u8 when set
        texture_window_x_mask: u8 = 0,
        texture_window_y_mask: u8 = 0,
        texture_window_x_offset: u8 = 0,
        texture_window_y_offset: u8 = 0,

        rectangle_texture_x_flip: u1 = 0,
        rectangle_texture_y_flip: u1 = 0,

        drawing_area_left: u32 = 0,
        drawing_area_top: u32 = 0,
        drawing_area_right: u32 = 1, // Exclusive
        drawing_area_bottom: u32 = 1, // Exclusive

        drawing_x_offset: i11 = 0,
        drawing_y_offset: i11 = 0,

        display_vram_x_start: u16 = 0, // FIXME Type
        display_vram_y_start: u16 = 0, // FIXME Type

        display_horiz_start: u16 = 0x200, // FIXME Type
        display_horiz_end: u16 = 0xc00, // FIXME Type

        display_line_start: u16 = 0x10, // FIXME Type
        display_line_end: u16 = 0x100, // FIXME Type
    } = .{},

    gp0_write_mode: GP0WriteMode = .idle,
    gpuread_mode: GPUReadMode = .idle, // FIXME not saved ATM
    gpuread_last_value: u32 = 0, // FIXME not saved ATM

    pending_vblank_ticks: u32 = 0,

    // FIXME not saved ATM
    backend: struct {
        pending_draw: bool = false, // Signals that the frame is ready to be drawn
        frame_index: u64 = 0,

        vertex_offset: u32 = 0,
        vertex_buffer: []PhatVertex,

        index_offset: u32 = 0,
        index_buffer: []u32,

        draw_command_buffer: []DrawCommand,
        draw_command_offset: u32 = 0,
    },

    // FIXME
    pub fn write(self: @This(), writer: anytype) !void {
        try writer.writeAll(std.mem.sliceAsBytes(self.vram_texels));

        try writer.writeStruct(self.regs, .little);

        switch (self.gp0_write_mode) {
            .idle => {
                try writer.writeByte(0);
            },
            .waiting_for_command_bytes => |state| {
                try writer.writeByte(1);
                try writer.writeStruct(state.op_code, .little);
                try writer.writeAll(&state.bytes);
                try writer.writeInt(@TypeOf(state.current_byte_index), state.current_byte_index, .little);
                try writer.writeInt(@TypeOf(state.command_size_bytes), state.command_size_bytes, .little);
            },
            .copy_rect_cpu_to_vram => |state| {
                try writer.writeByte(2);
                try writer.writeStruct(state.command, .little);
                try writer.writeInt(@TypeOf(state.index_x), state.index_x, .little);
                try writer.writeInt(@TypeOf(state.index_y), state.index_y, .little);
            },
        }

        try writer.writeInt(@TypeOf(self.pending_vblank_ticks), self.pending_vblank_ticks, .little);
    }

    // FIXME
    pub fn read(self: *@This(), reader: anytype) !void {
        try reader.readSliceAll(std.mem.sliceAsBytes(self.vram_texels));

        self.regs = try reader.takeStruct(@TypeOf(self.regs), .little);

        const gp0_write_mode_tag = try reader.takeByte();

        switch (gp0_write_mode_tag) {
            0 => self.gp0_write_mode = .idle,
            1 => {
                var state: GP0WriteMode.WaitingForCommandBytes = undefined;

                state.op_code = try reader.takeStruct(@TypeOf(state.op_code), .little);

                try reader.readSliceAll(&state.bytes);

                state.current_byte_index = try reader.takeInt(@TypeOf(state.current_byte_index), .little);
                state.command_size_bytes = try reader.takeInt(@TypeOf(state.command_size_bytes), .little);

                self.gp0_write_mode = .{ .waiting_for_command_bytes = state };
            },
            2 => {
                var state: CopyMode = undefined;

                state.command = try reader.takeStruct(@TypeOf(state.command), .little);
                state.index_x = try reader.takeInt(@TypeOf(state.index_x), .little);
                state.index_y = try reader.takeInt(@TypeOf(state.index_y), .little);

                self.gp0_write_mode = .{ .copy_rect_cpu_to_vram = state };
            },
            else => return error.InvalidGP0WriteMode,
        }

        self.pending_vblank_ticks = try reader.takeInt(@TypeOf(self.pending_vblank_ticks), .little);
    }
};

pub fn create_gpu_state(allocator: std.mem.Allocator) !GPUState {
    const vram_texels = try allocator.alloc(pixel_format.PackedRGB5A1, vram.TexelWidth * vram.TexelHeight);
    errdefer allocator.free(vram_texels);

    const vertex_buffer = try allocator.alloc(PhatVertex, 1_000_000); // FIXME
    errdefer allocator.free(vertex_buffer);

    const index_buffer = try allocator.alloc(u32, 1_000_000); // FIXME
    errdefer allocator.free(index_buffer);

    const draw_command_buffer = try allocator.alloc(DrawCommand, 1_000_000); // FIXME
    errdefer allocator.free(draw_command_buffer);

    return GPUState{
        .vram_texels = vram_texels,
        .backend = .{
            .vertex_buffer = vertex_buffer,
            .index_buffer = index_buffer,
            .draw_command_buffer = draw_command_buffer,
        },
    };
}

pub fn destroy_gpu_state(state: *GPUState, allocator: std.mem.Allocator) void {
    allocator.free(state.vram_texels);
    allocator.free(state.backend.vertex_buffer);
    allocator.free(state.backend.index_buffer);
    allocator.free(state.backend.draw_command_buffer);
}

pub const PhatVertex = struct {
    pos: f32_2,
    color: f32_3,
    tex: f32_2,
};

pub const f32_2 = @Vector(2, f32);
pub const f32_3 = @Vector(3, f32);

pub const DrawCommand = struct {
    //op_code: g0.OpCode,
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
pub const GPUType = 0x00_00_00_02; // New!

pub const GP0WriteMode = union(enum) {
    idle,
    waiting_for_command_bytes: WaitingForCommandBytes,
    copy_rect_cpu_to_vram: CopyMode,

    pub const WaitingForCommandBytes = struct {
        op_code: g0.OpCode,
        bytes: [g0.MaxCommandSizeBytes]u8 = undefined,
        current_byte_index: u32,
        command_size_bytes: u32,
    };
};

pub const GPUReadMode = union(enum) {
    idle,
    gpu_attributes,
    copy_rect_vram_to_cpu: CopyMode,
};

pub const CopyMode = struct {
    command: g0.CopyRectangleAcrossCPU,
    index_x: u32,
    index_y: u32,
};
