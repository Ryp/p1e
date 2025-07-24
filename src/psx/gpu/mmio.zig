const std = @import("std");

const PSXState = @import("../state.zig").PSXState;
const mmio = @import("../mmio.zig");

const execution = @import("execution.zig");

pub fn load_mmio_u32(psx: *PSXState, offset: u29) u32 {
    std.debug.assert(offset < MMIO.OffsetEnd);
    std.debug.assert(offset >= MMIO.Offset);

    const type_slice = mmio.get_mutable_mmio_slice_generic(u32, psx, offset);

    switch (offset) {
        MMIO.GPUREAD_Offset => {
            const value = std.mem.readInt(u32, type_slice, .little);

            std.debug.assert(value == 0);
            return value; // FIXME
        },
        MMIO.GPUSTAT_Offset => {
            // Update read-only registers
            psx.mmio.gpu.GPUSTAT.dma_data_request_mode = switch (psx.mmio.gpu.GPUSTAT.dma_direction) {
                .Off => 0,
                .Fifo => 1, // FIXME zero for full, one otherwise
                .CPUtoGP0 => psx.mmio.gpu.GPUSTAT.ready_to_recv_dma_block,
                .VRAMtoCPU => psx.mmio.gpu.GPUSTAT.ready_to_send_vram_to_cpu,
            };

            // FIXME Force vertical res to 240 lines to continue BIOS execution without proper sync support.
            var stat_value = psx.mmio.gpu.GPUSTAT;
            stat_value.vertical_resolution = ._240lines; // FIXME
            const stat_u32: u32 = @bitCast(stat_value);
            return stat_u32;

            // return std.mem.readInt(u32, type_slice, .little);
        },
        else => unreachable,
    }
}

pub fn store_mmio_u32(psx: *PSXState, offset: u29, value: u32) void {
    std.debug.assert(offset >= MMIO.Offset);
    std.debug.assert(offset < MMIO.OffsetEnd);

    switch (offset) {
        MMIO.G0_Offset => {
            execution.store_gp0_u32(psx, value);
        },
        MMIO.G1_Offset => {
            execution.execute_gp1_command(psx, @bitCast(value));
        },
        else => unreachable,
    }
}

pub const MMIO = struct {
    pub const Offset = 0x1f801810;
    pub const OffsetEnd = Offset + SizeBytes;

    pub const Packed = MMIO_GPU;

    const SizeBytes = mmio.MDEC_MMIO.Offset - Offset;

    const GPUREAD_Offset = 0x1f801810;
    const GPUSTAT_Offset = 0x1f801814;

    const G0_Offset = GPUREAD_Offset;
    const G1_Offset = GPUSTAT_Offset;

    comptime {
        std.debug.assert(@sizeOf(Packed) == SizeBytes);
    }
};

const MMIO_GPU = packed struct {
    // 1F801810h.Read  4   GPUREAD Read responses to GP0(C0h) and GP1(10h) commands
    // 1F801810h.Write 4   GP0 Send GP0 Commands/Packets (Rendering and VRAM Access)
    GPUREAD: packed struct {
        todo: u32 = 0, // FIXME
    } = .{},
    // 1F801814h.Read  4   GPUSTAT Read GPU Status Register
    // 1F801814h.Write 4   GP1 Send GP1 Commands (Display Control)
    GPUSTAT: packed struct { // Read-only
        texture_x_base: u4 = 0, // 0-3   Texture page X Base   (N*64)                              ;GP0(E1h).0-3
        texture_y_base: u1 = 0, // 4     Texture page Y Base   (N*256) (ie. 0 or 256)              ;GP0(E1h).4
        semi_transparency: u2 = 0, // 5-6   Semi Transparency     (0=B/2+F/2, 1=B+F, 2=B-F, 3=B+F/4)  ;GP0(E1h).5-6
        texture_page_colors: TexturePageColors = ._4bits, // 7-8 Texture page colors   (0=4bit, 1=8bit, 2=15bit, 3=Reserved)GP0(E1h).7-8
        dither_mode: u1 = 0, // 9 Dither 24bit to 15bit (0=Off/strip LSBs, 1=Dither Enabled);GP0(E1h).9
        draw_to_display_area: u1 = 0, //   10    Drawing to display area (0=Prohibited, 1=Allowed)         ;GP0(E1h).10
        // Set mask while drawing (0=TextureBit15, 1=ForceBit15=1)   ;GPUSTAT.11
        set_mask_when_drawing: u1 = 0, //   11    Set Mask-bit when drawing pixels (0=No, 1=Yes/Mask)       ;GP0(E6h).0
        // Check mask before draw (0=Draw Always, 1=Draw if Bit15=0) ;GPUSTAT.12
        check_mask_before_drawing: u1 = 0, //   12    Draw Pixels           (0=Always, 1=Not to Masked areas)   ;GP0(E6h).1
        interlace_field: u1 = 0, //   13    Interlace Field       (or, always 1 when GP1(08h).5=0)
        reverse_flag: u1 = 0, //   14    "Reverseflag"         (0=Normal, 1=Distorted)             ;GP1(08h).7
        texture_disable: u1 = 0, //   15    Texture Disable       (0=Normal, 1=Disable Textures)      ;GP0(E1h).11
        horizontal_resolution2: u1 = 0, //   16    Horizontal Resolution 2     (0=256/320/512/640, 1=368)    ;GP1(08h).6
        horizontal_resolution1: u2 = 0, //   17-18 Horizontal Resolution 1     (0=256, 1=320, 2=512, 3=640)  ;GP1(08h).0-1
        vertical_resolution: VerticalResolution = ._240lines, //   19    Vertical Resolution         (0=240, 1=480, when Bit22=1)  ;GP1(08h).2
        video_mode: VideoMode = .NTSC, //   20    Video Mode                  (0=NTSC/60Hz, 1=PAL/50Hz)     ;GP1(08h).3
        display_area_color_depth: DisplayAreaColorDepth = ._15bits, //   21    Display Area Color Depth    (0=15bit, 1=24bit)            ;GP1(08h).4
        vertical_interlace: u1 = 1, //   22    Vertical Interlace          (0=Off, 1=On)                 ;GP1(08h).5
        display_enabled: DisplayState = .Disabled, //   23    Display Enable              (0=Enabled, 1=Disabled)       ;GP1(03h).0
        interrupt_request: u1 = 0, //   24    Interrupt Request (IRQ1)    (0=Off, 1=IRQ)       ;GP0(1Fh)/GP1(02h)
        dma_data_request_mode: u1 = 0, //   25    DMA / Data Request, meaning depends on GP1(04h) DMA Direction:
        // When GP1(04h)=0 ---> Always zero (0)
        // When GP1(04h)=1 ---> FIFO State  (0=Full, 1=Not Full)
        // When GP1(04h)=2 ---> Same as GPUSTAT.28
        // When GP1(04h)=3 ---> Same as GPUSTAT.27
        ready_to_send_cmd: u1 = 1, // FIXME //   26    Ready to receive Cmd Word   (0=No, 1=Ready)  ;GP0(...) ;via GP0
        ready_to_send_vram_to_cpu: u1 = 1, // FIXME //   27    Ready to send VRAM to CPU   (0=No, 1=Ready)  ;GP0(C0h) ;via GPUREAD
        ready_to_recv_dma_block: u1 = 1, // FIXME  //   28    Ready to receive DMA Block  (0=No, 1=Ready)  ;GP0(...) ;via GP0
        dma_direction: DMADirection = .Off, // 29-30 DMA Direction
        drawing_even_odd_line_in_interlace_mode: u1 = 0, //   31    Drawing even/odd lines in interlace mode (0=Even or Vblank, 1=Odd)
        //
        // In 480-lines mode, bit31 changes per frame. And in 240-lines mode, the bit changes per scanline.
        // The bit is always zero during Vblank (vertical retrace and upper/lower screen border).
        //
        // Note
        // Further GPU status information can be retrieved via GP1(10h) and GP0(C0h).
        //
        // Ready Bits
        // Bit28: Normally, this bit gets cleared when the command execution is busy (ie. once when the command and all of its parameters are received),
        // however, for Polygon and Line Rendering commands, the bit gets cleared immediately after receiving the command word (ie. before receiving the vertex parameters).
        // The bit is used as DMA request in DMA Mode 2, accordingly, the DMA would probably hang if the Polygon/Line parameters are transferred in a separate DMA block (ie. the DMA probably starts ONLY on command words).
        // Bit27: Gets set after sending GP0(C0h) and its parameters, and stays set until all data words are received; used as DMA request in DMA Mode 3.
        // Bit26: Gets set when the GPU wants to receive a command. If the bit is cleared, then the GPU does either want to receive data,
        // or it is busy with a command execution (and doesn't want to receive anything).
        // Bit25: This is the DMA Request bit, however, the bit is also useful for non-DMA transfers, especially in the FIFO State mode.
    } = .{},
    _unused: u64 = undefined,

    pub const TexturePageColors = enum(u2) {
        _4bits,
        _8bits,
        _15bits,
        Reserved,
    };

    pub const VerticalResolution = enum(u1) {
        _240lines,
        _480lines,
    };

    pub const VideoMode = enum(u1) {
        NTSC,
        PAL,
    };

    pub const DisplayAreaColorDepth = enum(u1) {
        _15bits = 0,
        _24bits = 1,
    };

    pub const DisplayState = enum(u1) {
        Enabled = 0,
        Disabled = 1,
    };

    pub const DMADirection = enum(u2) {
        Off,
        Fifo,
        CPUtoGP0,
        VRAMtoCPU,
    };
};
