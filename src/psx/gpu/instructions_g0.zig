const std = @import("std");

const mmio = @import("mmio.zig");
const PackedRGB8 = @import("pixel_format.zig").PackedRGB8;

pub fn get_command_size_bytes(op_code: OpCode) u32 {
    switch (op_code.primary) {
        .Special => {
            switch (op_code.secondary.special) {
                .Nop => return 4,
                .FillRectangleInVRAM => return 3 * 4,
                .ClearCache, .InterruptRequest, .Unknown => return 4,
                _ => @panic("Unimplemented special opcode"),
            }
        },
        .DrawPoly => {
            const poly = op_code.secondary.draw_poly;

            if (poly.is_shaded) {
                if (poly.is_textured) {
                    const words: u32 = if (poly.is_quad) 12 else 9;
                    return words * 4;
                } else {
                    const words: u32 = if (poly.is_quad) 8 else 6;
                    return words * 4;
                }
            } else { // !poly.is_shaded
                if (poly.is_textured) {
                    const words: u32 = if (poly.is_quad) 9 else 7;
                    return words * 4;
                } else {
                    const words: u32 = if (poly.is_quad) 5 else 4;
                    return words * 4;
                }
            }
        },
        .DrawLine => {
            unreachable; // FIXME Variable
        },
        .DrawRect => {
            const rect = op_code.secondary.draw_rect;

            if (rect.is_textured) {
                const words: u32 = if (rect.size == .Variable) 4 else 3;
                return words * 4;
            } else {
                const words: u32 = if (rect.size == .Variable) 3 else 2;
                return words * 4;
            }
        },
        .CopyRectangleVRAMtoVRAM => {
            return 4 * 4;
        },
        .CopyRectangleCPUtoVRAM => {
            return 3 * 4;
        },
        .CopyRectangleVRAMtoCPU => {
            return 3 * 4;
        },
        .DrawModifier => {
            return 4;
        },
    }
}

// 00h = 000 00000 GP0(00h) - NOP (?)
// 01h = 000 00001 GP0(01h) - Clear Cache
// 02h = 000 00010 GP0(02h) - Fill Rectangle in VRAM
// 03h = 000 00011 GP0(03h) - Unknown?
// 1Fh = 000 11111 GP0(1Fh) - Interrupt Request (IRQ1)
//       001 xxxxx DrawPolyOpCode
//       010 xxxxx DrawLineOpCode
//       011 xxxxx DrawRectOpCode
// 80h = 100 xxxxx GP0(80h) - Copy Rectangle (VRAM to VRAM)
// A0h = 101 xxxxx GP0(A0h) - Copy Rectangle (CPU to VRAM)
// C0h = 110 xxxxx GP0(C0h) - Copy Rectangle (VRAM to CPU)
// E1h = 111 00001 GP0(E1h) - Draw Mode setting (aka "Texpage")
// E2h = 111 00010 GP0(E2h) - Texture Window setting
// E3h = 111 00011 GP0(E3h) - Set Drawing Area top left (X1,Y1)
// E4h = 111 00100 GP0(E4h) - Set Drawing Area bottom right (X2,Y2)
// E5h = 111 00101 GP0(E5h) - Set Drawing Offset (X,Y)
// E6h = 111 00110 GP0(E6h) - Mask Bit Setting
pub const OpCode = packed struct(u8) {
    secondary: packed union {
        special: SpecialOpCode,
        draw_poly: DrawPolyOpCode,
        draw_line: DrawLineOpCode,
        draw_rect: DrawRectOpCode,
        modifier: ModifierOpCode,
    },
    primary: PrimaryOpCode,
};

const PrimaryOpCode = enum(u3) {
    Special = 0b000,
    DrawPoly = 0b001,
    DrawLine = 0b010,
    DrawRect = 0b011,
    CopyRectangleVRAMtoVRAM = 0b100,
    CopyRectangleCPUtoVRAM = 0b101,
    CopyRectangleVRAMtoCPU = 0b110,
    DrawModifier = 0b111,
};

const SpecialOpCode = enum(u5) {
    Nop = 0b00000, // 00h
    ClearCache = 0b00001, // 01h = 0000 0001b GP0(01h) - Clear Cache
    FillRectangleInVRAM = 0b00010, // 02h = 0000 0010b GP0(02h) - Fill Rectangle in VRAM
    Unknown = 0b00011, // 03h = 0000 0011b GP0(03h) - Unknown?
    InterruptRequest = 0b11111, // 1Fh = 0001 1111b GP0(1Fh) - Interrupt Request (IRQ1)
    _, // Probably nop!
};

const ModifierOpCode = enum(u5) {
    SetDrawMode = 0b00001, // E1h = 1110 0001b GP0(E1h) - Draw Mode setting (aka "Texpage")
    SetTextureWindow = 0b00010, // E2h = 1110 0010b GP0(E2h) - Texture Window setting
    SetDrawingAreaTopLeft = 0b00011, // E3h = 1110 0011b GP0(E3h) - Set Drawing Area top left (X1,Y1)
    SetDrawingAreaBottomRight = 0b00100, // E4h = 1110 0100b GP0(E4h) - Set Drawing Area bottom right (X2,Y2)
    SetDrawingOffset = 0b00101, // E5h = 1110 0101b GP0(E5h) - Set Drawing Offset (X,Y)
    SetMaskBitSetting = 0b00110, // E6h = 1110 0110b GP0(E6h)- Mask Bit Setting
    _,
};

//       ___S QTtx
// 20h = 0010 0000b GP0(20h) - Monochrome three-point polygon, opaque
// 22h = 0010 0010b GP0(22h) - Monochrome three-point polygon, semi-transparent
// 28h = 0010 1000b GP0(28h) - Monochrome four-point polygon, opaque
// 2Ah = 0010 1010b GP0(2Ah) - Monochrome four-point polygon, semi-transparent
// 24h = 0010 0100b GP0(24h) - Textured three-point polygon, opaque, texture-blending
// 25h = 0010 0101b GP0(25h) - Textured three-point polygon, opaque, raw-texture
// 26h = 0010 0110b GP0(26h) - Textured three-point polygon, semi-transparent, texture-blending
// 27h = 0010 0111b GP0(27h) - Textured three-point polygon, semi-transparent, raw-texture
// 2Ch = 0010 1100b GP0(2Ch) - Textured four-point polygon, opaque, texture-blending
// 2Dh = 0010 1101b GP0(2Dh) - Textured four-point polygon, opaque, raw-texture
// 2Eh = 0010 1110b GP0(2Eh) - Textured four-point polygon, semi-transparent, texture-blending
// 2Fh = 0010 1111b GP0(2Fh) - Textured four-point polygon, semi-transparent, raw-texture
// 30h = 0011 0000b GP0(30h) - Shaded three-point polygon, opaque
// 32h = 0011 0010b GP0(32h) - Shaded three-point polygon, semi-transparent
// 38h = 0011 1000b GP0(38h) - Shaded four-point polygon, opaque
// 3Ah = 0011 1010b GP0(3Ah) - Shaded four-point polygon, semi-transparent
// 34h = 0011 0100b GP0(34h) - Shaded Textured three-point polygon, opaque, texture-blending
// 36h = 0011 0110b GP0(36h) - Shaded Textured three-point polygon, semi-transparent, tex-blend
// 3Ch = 0011 1100b GP0(3Ch) - Shaded Textured four-point polygon, opaque, texture-blending
// 3Eh = 0011 1110b GP0(3Eh) - Shaded Textured four-point polygon, semi-transparent, tex-blend
pub const DrawPolyOpCode = packed struct(u5) {
    texture_mode: DrawTextureMode,
    is_semi_transparent: bool,
    is_textured: bool,
    is_quad: bool,
    is_shaded: bool,
};

//       ___S STtr
// 60h = 0110 0000b GP0(60h) - Monochrome Rectangle, nxn opaque
// 62h = 0110 0010b GP0(62h) - Monochrome Rectangle, nxn semi-transparent
// 68h = 0110 1000b GP0(68h) - Monochrome Rectangle, 1x1 (Dot), opaque
// 6Ah = 0110 1010b GP0(6Ah) - Monochrome Rectangle, 1x1 (Dot), semi-transparent
// 70h = 0111 0000b GP0(70h) - Monochrome Rectangle, 8x8, opaque
// 72h = 0111 0010b GP0(72h) - Monochrome Rectangle, 8x8, semi-transparent
// 78h = 0111 1000b GP0(78h) - Monochrome Rectangle, 16x16, opaque
// 7Ah = 0111 1010b GP0(7Ah) - Monochrome Rectangle, 16x16, semi-transparent
// 64h = 0110 0100b GP0(64h) - Textured Rectangle, nxn opaque, texture-blending
// 65h = 0110 0101b GP0(65h) - Textured Rectangle, nxn opaque, raw-texture
// 66h = 0110 0110b GP0(66h) - Textured Rectangle, nxn semi-transparent, texture-blending
// 67h = 0110 0111b GP0(67h) - Textured Rectangle, nxn semi-transparent, raw-texture
// 6Ch = 0110 1100b GP0(6Ch) - Textured Rectangle, 1x1 (nonsense), opaque, texture-blending
// 6Dh = 0110 1101b GP0(6Dh) - Textured Rectangle, 1x1 (nonsense), opaque, raw-texture
// 6Eh = 0110 1110b GP0(6Eh) - Textured Rectangle, 1x1 (nonsense), semi-transparent, texture-blending
// 6Fh = 0110 1111b GP0(6Fh) - Textured Rectangle, 1x1 (nonsense), semi-transparent, raw-texture
// 74h = 0111 0100b GP0(74h) - Textured Rectangle, 8x8, opaque, texture-blending
// 75h = 0111 0101b GP0(75h) - Textured Rectangle, 8x8, opaque, raw-texture
// 76h = 0111 0110b GP0(76h) - Textured Rectangle, 8x8, semi-transparent, texture-blending
// 77h = 0111 0111b GP0(77h) - Textured Rectangle, 8x8, semi-transparent, raw-texture
// 7Ch = 0111 1100b GP0(7Ch) - Textured Rectangle, 16x16, opaque, texture-blending
// 7Dh = 0111 1101b GP0(7Dh) - Textured Rectangle, 16x16, opaque, raw-texture
// 7Eh = 0111 1110b GP0(7Eh) - Textured Rectangle, 16x16, semi-transparent, texture-blending
// 7Fh = 0111 1111b GP0(7Fh) - Textured Rectangle, 16x16, semi-transparent, raw-texture
pub const DrawRectOpCode = packed struct(u5) {
    texture_mode: DrawTextureMode,
    is_semi_transparent: bool,
    is_textured: bool,
    size: enum(u2) {
        Variable,
        _1x1,
        _8x8,
        _16x16,
    },
};

const DrawTextureMode = enum(u1) {
    Blended,
    Raw,
};

//       ___S PTt0
// 40h = 0100 0000b GP0(40h) - Monochrome line, opaque
// 42h = 0100 0010b GP0(42h) - Monochrome line, semi-transparent
// 48h = 0100 1000b GP0(48h) - Monochrome Poly-line, opaque
// 4Ah = 0100 1010b GP0(4Ah) - Monochrome Poly-line, semi-transparent
// 50h = 0101 0000b GP0(50h) - Shaded line, opaque
// 52h = 0101 0010b GP0(52h) - Shaded line, semi-transparent
// 58h = 0101 1000b GP0(58h) - Shaded Poly-line, opaque
// 5Ah = 0101 1010b GP0(5Ah) - Shaded Poly-line, semi-transparent
const DrawLineOpCode = packed struct(u5) {
    zero_b0: bool,
    is_semi_transparent: bool,
    zero_b1: bool,
    is_poly_line: bool,
    is_shaded: bool,
};

pub const Noop = packed struct(u32) {
    unknown_b0_23: u24,
    op_code: OpCode,
};

pub const ClearTextureCache = packed struct(u32) {
    zero_b0_23: u24,
    op_code: OpCode,
};

pub const FillRectangleInVRAM = packed struct(u96) {
    color: PackedRGB8,
    op_code: OpCode, // 1st  Color+Command     (CcBbGgRrh)  ;24bit RGB value (see note)
    position_top_left: PackedVertexPos, // 2nd  Top Left Corner   (YyyyXxxxh)  ;Xpos counted in halfwords, steps of 10h
    size: PackedVertexPos, //  3rd Width+Height      (YsizXsizh)  ;Xsiz counted in halfwords, steps of 10h
};

pub const DrawTriangleMonochrome = packed struct {
    color: PackedRGB8,
    op_code: OpCode,

    v1_pos: PackedVertexPos,
    v2_pos: PackedVertexPos,
    v3_pos: PackedVertexPos,
};

pub const DrawQuadMonochrome = packed struct {
    color: PackedRGB8,
    op_code: OpCode,

    v1_pos: PackedVertexPos,
    v2_pos: PackedVertexPos,
    v3_pos: PackedVertexPos,
    v4_pos: PackedVertexPos,
};

pub const DrawTriangleTextured = packed struct {
    color: PackedRGB8,
    op_code: OpCode,

    v1_pos: PackedVertexPos,
    v1_texcoord: PackedTexCoord,
    palette: PackedClut,

    v2_pos: PackedVertexPos,
    v2_texcoord: PackedTexCoord,
    tex_page: PackedTexPage,

    v3_pos: PackedVertexPos,
    v3_texcoord: PackedTexCoord,
    zero_v3_b16_31: u16,
};

pub const DrawQuadTextured = packed struct {
    color: PackedRGB8,
    op_code: OpCode,
    v1_pos: PackedVertexPos,
    v1_texcoord: PackedTexCoord,
    palette: PackedClut,

    v2_pos: PackedVertexPos,
    v2_texcoord: PackedTexCoord,
    tex_page: PackedTexPage,

    v3_pos: PackedVertexPos,
    v3_texcoord: PackedTexCoord,
    zero_v3_b16_31: u16,

    v4_pos: PackedVertexPos,
    v4_texcoord: PackedTexCoord,
    zero_v4_b16_31: u16,
};

pub const DrawTriangleShaded = packed struct {
    v1_color: PackedRGB8,
    op_code: OpCode,
    v1_pos: PackedVertexPos,

    v2_color: PackedRGB8,
    v2_unused: u8,
    v2_pos: PackedVertexPos,

    v3_color: PackedRGB8,
    v3_unused: u8,
    v3_pos: PackedVertexPos,
};

pub const DrawQuadShaded = packed struct {
    v1_color: PackedRGB8,
    op_code: OpCode,
    v1_pos: PackedVertexPos,

    v2_color: PackedRGB8,
    v2_unused: u8,
    v2_pos: PackedVertexPos,

    v3_color: PackedRGB8,
    v3_unused: u8,
    v3_pos: PackedVertexPos,

    v4_color: PackedRGB8,
    v4_unused: u8,
    v4_pos: PackedVertexPos,
};

pub const DrawTriangleShadedTextured = packed struct {
    v1_color: PackedRGB8,
    op_code: OpCode,
    v1_pos: PackedVertexPos,
    v1_texcoord: PackedTexCoord,
    palette: PackedClut,

    v2_color: PackedRGB8,
    v2_unused: u8,
    v2_pos: PackedVertexPos,
    v2_texcoord: PackedTexCoord,
    tex_page: PackedTexPage,

    v3_color: PackedRGB8,
    v3_unused: u8,
    v3_pos: PackedVertexPos,
    v3_texcoord: PackedTexCoord,
    zero_v3_b16_31: u16,
};

pub const DrawQuadShadedTextured = packed struct {
    v1_color: PackedRGB8,
    op_code: OpCode,
    v1_pos: PackedVertexPos,
    v1_texcoord: PackedTexCoord,
    palette: PackedClut,

    v2_color: PackedRGB8,
    v2_unused: u8,
    v2_pos: PackedVertexPos,
    v2_texcoord: PackedTexCoord,
    tex_page: PackedTexPage,

    v3_color: PackedRGB8,
    v3_unused: u8,
    v3_pos: PackedVertexPos,
    v3_texcoord: PackedTexCoord,
    zero_v3_b16_31: u16,

    v4_color: PackedRGB8,
    v4_unused: u8,
    v4_pos: PackedVertexPos,
    v4_texcoord: PackedTexCoord,
    zero_v4_b16_31: u16,
};

// Rect
pub const DrawRectMonochrome = packed struct(u64) {
    color: PackedRGB8,
    op_code: OpCode,
    position_top_left: PackedVertexPos,
};

pub const DrawRectMonochromeVariable = packed struct(u96) {
    base_command: DrawRectMonochrome,
    extent: PackedVertexPos,
};

pub const DrawRectTextured = packed struct(u96) {
    color: PackedRGB8,
    op_code: OpCode,

    position_top_left: PackedVertexPos,

    position_texcoord: PackedTexCoord,
    palette: PackedClut,
};

pub const DrawRectTexturedVariable = packed struct(u128) {
    base_command: DrawRectTextured,
    extent: PackedVertexPos,
};

// Primitives
pub const PackedVertexPos = packed struct(u32) {
    x: u16,
    y: u16,
};

pub const PackedTexCoord = packed struct(u16) {
    x: u8,
    y: u8,
};

pub const PackedClut = packed struct(u16) {
    x: u6, //   0-5      X coordinate X/16  (ie. in 16-halfword steps)
    y: u9, // 6-14     Y coordinate 0-511 (ie. in 1-line steps)
    zero: u1,
};

pub const PackedTexPage = packed struct(u16) {
    // 0-8    Same as GP0(E1h).Bit0-8 (see there)
    texture_x_base: u4,
    texture_y_base: u1,
    semi_transparency_mode: mmio.MMIO.Packed.SemiTransparency,
    texture_page_colors: mmio.MMIO.Packed.TexturePageColors,

    unused_b9_10: u2, // 9-10   Unused (does NOT change GP0(E1h).Bit9-10)

    texture_disable: u1, // 11     Same as GP0(E1h).Bit11  (see there)

    unused_b12_13: u2, // 12-13  Unused (does NOT change GP0(E1h).Bit12-13)
    zero_b14_15: u2, // 14-15  Unused (should be 0)
};

pub const CopyRectangleInVRAM = packed struct(u128) {
    zero_b0_23: u24,
    op_code: OpCode,
    position_top_left_src: PackedVertexPos,
    position_top_left_dst: PackedVertexPos,
    size: PackedVertexPos,
};

pub const CopyRectangleAcrossCPU = packed struct(u96) {
    zero_b0_23: u24,
    op_code: OpCode,
    position_top_left: PackedVertexPos,
    size: PackedVertexPos,
};

pub const SetDrawMode = packed struct(u32) {
    texture_x_base: u4,
    texture_y_base: u1,
    semi_transparency_mode: mmio.MMIO.Packed.SemiTransparency,
    texture_page_colors: mmio.MMIO.Packed.TexturePageColors,
    dither_mode: u1,
    draw_to_display_area: mmio.MMIO.Packed.DrawToDisplayArea,
    texture_disable: u1,
    rectangle_texture_x_flip: u1,
    rectangle_texture_y_flip: u1,
    zero_b14_23: u10,
    op_code: OpCode,
};

pub const SetTextureWindow = packed struct(u32) {
    mask_x: u5,
    mask_y: u5,
    offset_x: u5,
    offset_y: u5,
    zero_b20_23: u4,
    op_code: OpCode,
};

pub const SetDrawingAreaTopLeft = packed struct(u32) {
    left: u10,
    top: u10,
    zero_b20_23: u4,
    op_code: OpCode,
};

pub const SetDrawingAreaBottomRight = packed struct(u32) {
    right: u10,
    bottom: u10,
    zero_b20_23: u4,
    op_code: OpCode,
};

pub const SetDrawingOffset = packed struct(u32) {
    x: i11,
    y: i11,
    zero_b22_23: u2,
    op_code: OpCode,
};

pub const SetMaskBitSetting = packed struct(u32) {
    set_mask_when_drawing: u1,
    check_mask_before_drawing: u1,
    zero_b2_23: u22,
    op_code: OpCode,
};

pub const MaxCommandSizeBytes = 48 * 4; // FIXME use comptime fn?

// FIXME Assert better, because demons can hide here very easily!
comptime {
    std.debug.assert(4 == @sizeOf(Noop));
    std.debug.assert(4 == @sizeOf(ClearTextureCache));
    std.debug.assert(16 == @sizeOf(DrawTriangleMonochrome));
    // FIXME https://github.com/ziglang/zig/issues/20647#issuecomment-2241509633
    // std.debug.assert(20 == @sizeOf(DrawQuadMonochrome));
    // std.debug.assert(24 == @sizeOf(DrawTriangleShaded));
    std.debug.assert(32 == @sizeOf(DrawQuadShaded));
    // std.debug.assert(12 == @sizeOf(CopyRectangleAcrossCPU));
    std.debug.assert(4 == @sizeOf(SetDrawMode));
    std.debug.assert(4 == @sizeOf(SetTextureWindow));
    std.debug.assert(4 == @sizeOf(SetDrawingAreaTopLeft));
    std.debug.assert(4 == @sizeOf(SetDrawingAreaBottomRight));
    std.debug.assert(4 == @sizeOf(SetDrawingOffset));
    std.debug.assert(4 == @sizeOf(SetMaskBitSetting));
}
