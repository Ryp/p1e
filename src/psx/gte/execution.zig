const std = @import("std");

const config = @import("../config.zig");
const state = @import("state.zig");
const instructions = @import("instructions.zig");
const GTERegisters = state.GTERegisters;
const PSXState = @import("../state.zig").PSXState;

const i32_3 = @Vector(3, i32);
const i44_3 = @Vector(3, i44);

pub fn load_data_reg(regs: *const GTERegisters, register: GTERegisters.DataRegister) u32 {
    if (config.enable_gte_debug) {
        std.debug.print("GTE data load {}\n", .{register});
    }

    return switch (register) {
        .VZ0, .VZ1, .VZ2, .IR0, .IR1, .IR2, .IR3 => { // Sign extended
            const value_u16: u16 = @truncate(regs.raw.data[@backingInt(register)]);
            const value_sign_extended: i32 = @as(i16, @bitCast(value_u16));
            return @bitCast(value_sign_extended);
        },
        .SZ0, .SZ1, .SZ2, .SZ3 => { // Zero extended
            const value_u16: u16 = @truncate(regs.raw.data[@backingInt(register)]);
            return value_u16;
        },
        .OTZ => regs.raw.data[@backingInt(register)], // Computed on command execution
        .SXP_SYP => @bitCast(regs.typed.S2),
        .IRGB, .ORGB => {
            const color: state.ColorRGB5_u32 = .{
                .r = @intCast(std.math.clamp(regs.typed.IR1 >> 7, 0, std.math.maxInt(u5))),
                .g = @intCast(std.math.clamp(regs.typed.IR2 >> 7, 0, std.math.maxInt(u5))),
                .b = @intCast(std.math.clamp(regs.typed.IR3 >> 7, 0, std.math.maxInt(u5))),
            };
            return @bitCast(color);
        },
        else => regs.raw.data[@backingInt(register)],
    };
}

// We don't truncate when registers only have 16 bit values.
// Just make sure the unused bits don't get read.
pub fn store_data_reg(regs: *GTERegisters, register: GTERegisters.DataRegister, value: u32) void {
    if (config.enable_gte_debug) {
        std.debug.print("GTE data store {} with {x}\n", .{ register, value });
    }

    switch (register) {
        .SXP_SYP => {
            push_position_xy_fifo(&regs.typed, @bitCast(value));
        },
        .OTZ => regs.typed.OTZ = @bitCast(@as(u16, @truncate(value))),
        .IRGB => {
            const color: state.ColorRGB5_u32 = @bitCast(value);
            regs.typed.IR1 = @as(u12, color.r) << 7;
            regs.typed.IR2 = @as(u12, color.g) << 7;
            regs.typed.IR3 = @as(u12, color.b) << 7;
        },
        .ORGB => {}, // Write ignored
        .LZCS => {
            const mask: i32 = @bitCast(value);
            regs.typed.LZCS = mask;
            regs.typed.LZCR = if (mask < 0) @clz(~mask) else @clz(mask);
        },
        .LZCR => {}, // Write ignored
        else => regs.raw.data[@backingInt(register)] = value,
    }
}

pub fn load_ctrl_reg(regs: *const GTERegisters, register: GTERegisters.CtrlRegister) u32 {
    if (config.enable_gte_debug) {
        std.debug.print("GTE ctrl load {}\n", .{register});
    }

    return switch (register) {
        .H, .DQA, .ZSF3, .ZSF4, .RT33, .L33, .LB3 => { // Sign-extension
            const value_u16: u16 = @truncate(regs.raw.ctrl[@backingInt(register)]);
            const value_sign_extended: i32 = @as(i16, @bitCast(value_u16));
            return @bitCast(value_sign_extended);
        },
        else => regs.raw.ctrl[@backingInt(register)],
    };
}

// We don't truncate when registers only have 16 bit values.
// Just make sure the unused bits don't get read.
pub fn store_ctrl_reg(regs: *GTERegisters, register: GTERegisters.CtrlRegister, value: u32) void {
    if (config.enable_gte_debug) {
        std.debug.print("GTE ctrl store {} with {x}\n", .{ register, value });
    }

    switch (register) {
        .FLAG => {
            regs.raw.ctrl[@backingInt(register)] = value;

            regs.typed.FLAG.unused_b0_11 = 0;
            regs.typed.FLAG.err = regs.raw.ctrl[@backingInt(register)] & 0x7f87e000 != 0;
        },
        else => regs.raw.ctrl[@backingInt(register)] = value,
    }
}

pub fn execute(psx: *PSXState, instruction: instructions.GTECommand) void {
    if (config.enable_gte_debug) {
        std.debug.print("GTE instruction {}\n", .{instruction});
    }

    const typed_regs = &psx.gte.regs.typed;

    typed_regs.FLAG = @bitCast(@as(u32, 0));

    switch (instruction.opcode) {
        .RTPS => execute_rtps(typed_regs, instruction),
        .RTPT => execute_rtpt(typed_regs, instruction),
        .MVMVA => execute_mvmva(typed_regs, instruction),
        .DCPL => execute_dcpl(typed_regs, instruction),
        .DPCS => execute_dpcs(typed_regs, instruction),
        .DPCT => execute_dpct(typed_regs, instruction),
        .INTPL => execute_intpl(typed_regs, instruction),
        .SQR_sf => execute_sqr_sf(typed_regs, instruction),
        .NCS => execute_ncs(typed_regs, instruction),
        .NCT => execute_nct(typed_regs, instruction),
        .NCDS => execute_ncds(typed_regs, instruction),
        .NCDT => execute_ncdt(typed_regs, instruction),
        .NCCS => execute_nccs(typed_regs, instruction),
        .NCCT => execute_ncct(typed_regs, instruction),
        .CDP => execute_cdp(typed_regs, instruction),
        .CC => execute_cc(typed_regs, instruction),
        .NCLIP => execute_nclip(typed_regs, instruction),
        .AVSZ3 => execute_avsz(typed_regs, .AVSZ3),
        .AVSZ4 => execute_avsz(typed_regs, .AVSZ4),
        .OP_sf => execute_op_sf(typed_regs, instruction),
        .GPF_sf => execute_gpf_sf(typed_regs, instruction),
        .GPL_sf => execute_gpl_sf(typed_regs, instruction),
        _ => if (config.enable_gte_debug) {
            std.debug.print("Invalid GTE opcode {}\n", .{instruction.opcode});
        },
    }

    typed_regs.FLAG.err = @as(u32, @bitCast(typed_regs.FLAG)) & 0x7f87e000 != 0;
}

fn execute_rtps(r: *GTERegisters.Typed, instruction: instructions.GTECommand) void {
    execute_rtp(r, instruction, &r.V0, true);
}

fn execute_rtpt(r: *GTERegisters.Typed, instruction: instructions.GTECommand) void {
    inline for (.{ &r.V0, &r.V1, &r.V2 }, 0..) |vector, i| {
        execute_rtp(r, instruction, vector, i == 2);
    }
}

fn execute_rtp(r: *GTERegisters.Typed, instruction: instructions.GTECommand, vector: *GTERegisters.Vector, depth_cue: bool) void {
    // IR1 = MAC1 = (TRX*1000h + RT11*VX0 + RT12*VY0 + RT13*VZ0) SAR (sf*12)
    // IR2 = MAC2 = (TRY*1000h + RT21*VX0 + RT22*VY0 + RT23*VZ0) SAR (sf*12)
    // IR3 = MAC3 = (TRZ*1000h + RT31*VX0 + RT32*VY0 + RT33*VZ0) SAR (sf*12)
    const offset: i32_3 = .{ r.TRX, r.TRY, r.TRZ };

    var mac3: i44 = undefined;
    execute_generic_mat_mul(r, .{ .rtp = .{ .mac3 = &mac3 } }, &r.RT, vector, offset, instruction.sf, instruction.lm);

    // SZ3 = MAC3 SAR ((1-sf)*12)                           ;ScreenZ FIFO 0..+FFFFh
    const sz = mac3 >> 12;
    const sz_sat: u16 = @intCast(std.math.clamp(sz, 0, std.math.maxInt(u16)));

    r.FLAG.sz_saturated |= sz_sat != sz;

    push_position_z_fifo(r, sz_sat);

    r.FLAG.ir3_saturated |= sz < std.math.minInt(i16) or sz > std.math.maxInt(i16);

    // MAC0=(((H*20000h/SZ3)+1)/2)*IR1+OFX, SX2=MAC0/10000h ;ScrX FIFO -400h..+3FFh
    // MAC0=(((H*20000h/SZ3)+1)/2)*IR2+OFY, SY2=MAC0/10000h ;ScrY FIFO -400h..+3FFh
    // MAC0=(((H*20000h/SZ3)+1)/2)*DQA+DQB, IR0=MAC0/1000h  ;Depth cueing 0..+1000h
    const div_overflow = r.H >= @as(u17, r.SZ3) * 2;
    const div: i44 = if (!div_overflow) @intCast(h_div_sz3(r)) else std.math.maxInt(u17);

    r.FLAG.div_overflow |= div_overflow;

    const mac0_x: i44 = div * r.IR1 + r.OFX;
    const mac0_y: i44 = div * r.IR2 + r.OFY;
    const mac0_z: i44 = div * r.DQA + r.DQB;

    const sx = mac0_x >> 16;
    const sy = mac0_y >> 16;
    const ir0 = mac0_z >> 12;

    const sx_sat: i11 = @intCast(std.math.clamp(sx, std.math.minInt(i11), std.math.maxInt(i11)));
    const sy_sat: i11 = @intCast(std.math.clamp(sy, std.math.minInt(i11), std.math.maxInt(i11)));
    const ir0_sat: u13 = @intCast(std.math.clamp(ir0, 0, 0x1000));

    r.MAC0 = @truncate(mac0_x);
    r.FLAG.mac0_wrapped_negative |= mac0_x < std.math.minInt(i32);
    r.FLAG.mac0_wrapped_positive |= mac0_x > std.math.maxInt(i32);

    r.MAC0 = @truncate(mac0_y);
    r.FLAG.mac0_wrapped_negative |= mac0_y < std.math.minInt(i32);
    r.FLAG.mac0_wrapped_positive |= mac0_y > std.math.maxInt(i32);

    push_position_xy_fifo(r, .{ .x = sx_sat, .y = sy_sat });
    r.FLAG.sx_saturated |= sx_sat != sx;
    r.FLAG.sy_saturated |= sy_sat != sy;

    if (depth_cue) {
        r.MAC0 = @truncate(mac0_z);
        r.FLAG.mac0_wrapped_positive |= mac0_z > std.math.maxInt(i32);
        r.FLAG.mac0_wrapped_negative |= mac0_z < std.math.minInt(i32);

        r.IR0 = ir0_sat;
        r.FLAG.ir0_saturated |= ir0_sat != ir0;
    }
}

// Reciprocal seeds: round(20000h / (i + 100h)) - 101h, clamped to zero
const UnsignedNewtonRaphsonTable: [0x101]u8 = blk: {
    var table: [0x101]u8 = undefined;
    for (&table, 0..) |*entry, i| {
        const value: i32 = @divTrunc(@divTrunc(0x40000, @as(i32, @intCast(i)) + 0x100) + 1, 2) - 0x101;
        entry.* = @intCast(@max(0, value));
    }
    break :blk table;
};

// Computes (((H*20000h/SZ3)+1)/2)
//
// z = count_leading_zeroes(SZ3)                ;z=0..0Fh (for 16bit SZ3)
// n = (H SHL z)                                ;n=0..7FFF8000h
// d = (SZ3 SHL z)                              ;d=8000h..FFFFh
// u = unr_table[(d-7FC0h) SHR 7] + 101h        ;u=200h..101h
// d = ((2000080h - (d * u)) SHR 8)             ;d=10000h..0FF01h
// d = ((0000080h + (d * u)) SHR 8)             ;d=20000h..10000h
// n = min(1FFFFh, (((n*d) + 8000h) SHR 16))    ;n=0..1FFFFh
fn h_div_sz3(r: *GTERegisters.Typed) i64 {
    const shift: u4 = @intCast(@clz(r.SZ3)); // Safe to cast because SZ3 is non-zero therefore 16 cannot be reached.
    const n: i64 = @as(i64, r.H) << shift;
    const d: i64 = @shlExact(r.SZ3, shift);

    const seed: i64 = 0x101 + @as(i64, UnsignedNewtonRaphsonTable[@intCast(((d & 0x7fff) + 0x40) >> 7)]);

    const correction: i64 = (0x02_00_00_80 - d * seed) >> 8;
    const reciprocal: i64 = (0x00_00_00_80 + correction * seed) >> 8;

    return @min((n * reciprocal + 0x8000) >> 16, std.math.maxInt(u17));
}

// COP2 0400012h - 8 Cycles - MVMVA(sf,mx,v,cv,lm)
//
// Multiply vector by matrix and vector addition.
//
//   Mx = matrix specified by mx  ;RT/LLM/LCM - Rotation, light or color matrix
//   Vx = vector specified by v   ;V0, V1, V2, or [IR1,IR2,IR3]
//   Tx = translation vector specified by cv  ;TR or BK or Bugged/FC, or None
//
// Calculation:
//
//   MAC1 = (Tx1*1000h + Mx11*Vx1 + Mx12*Vx2 + Mx13*Vx3) SAR (sf*12)
//   MAC2 = (Tx2*1000h + Mx21*Vx1 + Mx22*Vx2 + Mx23*Vx3) SAR (sf*12)
//   MAC3 = (Tx3*1000h + Mx31*Vx1 + Mx32*Vx2 + Mx33*Vx3) SAR (sf*12)
//   [IR1,IR2,IR3] = [MAC1,MAC2,MAC3]
//
// Multiplies a vector with either the rotation matrix, the light matrix
// or the color matrix and then adds the translation vector or background color vector.
// The GTE also allows selection of the far color vector (FC),
// but this vector is not added correctly by the hardware: The return values are reduced to the last two portions of the formula
// ie. MAC1=(Mx12*Vx2+Mx13*Vx3) SAR (sf*12), and similar for MAC2 and MAC3, nevertheless,
// some bits in the FLAG register seem to be adjusted as if the full operation would have been executed.
// Setting Mx=3 selects a garbage matrix (with elements -R*10h, +R*10h, IR0, RT13, RT13, RT13, RT22, RT22, RT22),
// where R is the red component of RGBC (ie. RGBC[0] multiplied by 10h, negated for the first element).
fn execute_mvmva(r: *GTERegisters.Typed, instruction: instructions.GTECommand) void {
    const reserved_matrix = GTERegisters.MatrixType{
        .m11 = -(@as(i16, r.RGBC.r) << 4),
        .m12 = @as(i16, r.RGBC.r) << 4,
        .m13 = r.IR0,
        .m21 = r.RT.m13,
        .m22 = r.RT.m13,
        .m23 = r.RT.m13,
        .m31 = r.RT.m22,
        .m32 = r.RT.m22,
        .m33 = r.RT.m22,
    };

    const matrix = switch (instruction.mvmva_matrix) {
        .Rotation => &r.RT,
        .Light => &r.LLM,
        .Color => &r.LCM,
        .Reserved => &reserved_matrix,
    };

    const vector: GTERegisters.Vector = switch (instruction.mvmva_vector) {
        .V0 => r.V0,
        .V1 => r.V1,
        .V2 => r.V2,
        .IR => .{ .x = r.IR1, .y = r.IR2, .z = r.IR3 },
    };

    const translate: i32_3 = switch (instruction.mvmva_translation) {
        .TR => .{ r.TRX, r.TRY, r.TRZ },
        .BK => .{ r.RBK, r.GBK, r.BBK },
        .FC_Bugged => .{ r.RFC, r.GFC, r.BFC },
        .None => .{ 0, 0, 0 },
    };

    if (instruction.mvmva_translation == .FC_Bugged) {
        execute_generic_mat_mul(r, .broken_fc, matrix, &vector, translate, instruction.sf, instruction.lm);
    } else {
        execute_mat_mul(r, matrix, &vector, translate, instruction.sf, instruction.lm);
    }
}

fn execute_mat_mul(r: *GTERegisters.Typed, matrix: *const GTERegisters.MatrixType, vector: *const GTERegisters.Vector, translate: i32_3, sf: bool, lm: bool) void {
    execute_generic_mat_mul(r, .normal, matrix, vector, translate, sf, lm);
}

const Tweak = union(enum) {
    normal,
    rtp: struct {
        mac3: *i44,
    },
    broken_fc,
};

fn execute_generic_mat_mul(r: *GTERegisters.Typed, tweak: Tweak, matrix: *const GTERegisters.MatrixType, vector: *const GTERegisters.Vector, translate: i32_3, sf: bool, lm: bool) void {
    var mac1 = @shlExact(@as(i44, translate[0]), 12);
    var mac2 = @shlExact(@as(i44, translate[1]), 12);
    var mac3 = @shlExact(@as(i44, translate[2]), 12);

    var mac1_overflow: u1 = undefined;
    var mac2_overflow: u1 = undefined;
    var mac3_overflow: u1 = undefined;

    mac1, mac1_overflow = @addWithOverflow(mac1, std.math.mulWide(i16, matrix.m11, vector.x));
    mac2, mac2_overflow = @addWithOverflow(mac2, std.math.mulWide(i16, matrix.m21, vector.x));
    mac3, mac3_overflow = @addWithOverflow(mac3, std.math.mulWide(i16, matrix.m31, vector.x));

    r.FLAG.mac1_wrapped_negative |= if (mac1_overflow != 0) mac1 > 0 else false;
    r.FLAG.mac1_wrapped_positive |= if (mac1_overflow != 0) mac1 < 0 else false;
    r.FLAG.mac2_wrapped_negative |= if (mac2_overflow != 0) mac2 > 0 else false;
    r.FLAG.mac2_wrapped_positive |= if (mac2_overflow != 0) mac2 < 0 else false;
    r.FLAG.mac3_wrapped_negative |= if (mac3_overflow != 0) mac3 > 0 else false;
    r.FLAG.mac3_wrapped_positive |= if (mac3_overflow != 0) mac3 < 0 else false;

    if (tweak == .broken_fc) {
        r.MAC1 = mac_sar12_raw(mac1, sf);
        r.MAC2 = mac_sar12_raw(mac2, sf);
        r.MAC3 = mac_sar12_raw(mac3, sf);

        r.IR1 = @intCast(std.math.clamp(r.MAC1, std.math.minInt(i16), std.math.maxInt(i16)));
        r.IR2 = @intCast(std.math.clamp(r.MAC2, std.math.minInt(i16), std.math.maxInt(i16)));
        r.IR3 = @intCast(std.math.clamp(r.MAC3, std.math.minInt(i16), std.math.maxInt(i16)));

        r.FLAG.ir1_saturated |= r.IR1 != r.MAC1;
        r.FLAG.ir2_saturated |= r.IR2 != r.MAC2;
        r.FLAG.ir3_saturated |= r.IR3 != r.MAC3;

        mac1 = 0;
        mac2 = 0;
        mac3 = 0;
    }

    mac1, mac1_overflow = @addWithOverflow(mac1, std.math.mulWide(i16, matrix.m12, vector.y));
    mac2, mac2_overflow = @addWithOverflow(mac2, std.math.mulWide(i16, matrix.m22, vector.y));
    mac3, mac3_overflow = @addWithOverflow(mac3, std.math.mulWide(i16, matrix.m32, vector.y));

    r.FLAG.mac1_wrapped_negative |= if (mac1_overflow != 0) mac1 > 0 else false;
    r.FLAG.mac1_wrapped_positive |= if (mac1_overflow != 0) mac1 < 0 else false;
    r.FLAG.mac2_wrapped_negative |= if (mac2_overflow != 0) mac2 > 0 else false;
    r.FLAG.mac2_wrapped_positive |= if (mac2_overflow != 0) mac2 < 0 else false;
    r.FLAG.mac3_wrapped_negative |= if (mac3_overflow != 0) mac3 > 0 else false;
    r.FLAG.mac3_wrapped_positive |= if (mac3_overflow != 0) mac3 < 0 else false;

    mac1, mac1_overflow = @addWithOverflow(mac1, std.math.mulWide(i16, matrix.m13, vector.z));
    mac2, mac2_overflow = @addWithOverflow(mac2, std.math.mulWide(i16, matrix.m23, vector.z));
    mac3, mac3_overflow = @addWithOverflow(mac3, std.math.mulWide(i16, matrix.m33, vector.z));

    r.FLAG.mac1_wrapped_negative |= if (mac1_overflow != 0) mac1 > 0 else false;
    r.FLAG.mac1_wrapped_positive |= if (mac1_overflow != 0) mac1 < 0 else false;
    r.FLAG.mac2_wrapped_negative |= if (mac2_overflow != 0) mac2 > 0 else false;
    r.FLAG.mac2_wrapped_positive |= if (mac2_overflow != 0) mac2 < 0 else false;
    r.FLAG.mac3_wrapped_negative |= if (mac3_overflow != 0) mac3 > 0 else false;
    r.FLAG.mac3_wrapped_positive |= if (mac3_overflow != 0) mac3 < 0 else false;

    r.MAC1 = mac_sar12_raw(mac1, sf);
    r.MAC2 = mac_sar12_raw(mac2, sf);
    r.MAC3 = mac_sar12_raw(mac3, sf);

    const ir_lm_min: i16 = if (lm) 0 else std.math.minInt(i16);

    r.IR1 = @intCast(std.math.clamp(r.MAC1, ir_lm_min, std.math.maxInt(i16)));
    r.IR2 = @intCast(std.math.clamp(r.MAC2, ir_lm_min, std.math.maxInt(i16)));
    r.IR3 = @intCast(std.math.clamp(r.MAC3, ir_lm_min, std.math.maxInt(i16)));

    r.FLAG.ir1_saturated |= r.IR1 != r.MAC1;
    r.FLAG.ir2_saturated |= r.IR2 != r.MAC2;

    switch (tweak) {
        .rtp => |n| n.mac3.* = mac3,
        else => r.FLAG.ir3_saturated |= r.IR3 != r.MAC3,
    }
}

// COP2 0680029h - 8 Cycles - DCPL - Depth Cue Color light
//
// In: [IR1,IR2,IR3]=Vector, FC=Far Color, IR0=Interpolation value, CODE=MSB of RGBC, and, for DCPL, R,G,B=LSBs of RGBC.
//
// [MAC1,MAC2,MAC3] = [R*IR1,G*IR2,B*IR3] SHL 4          ;<--- for DCPL only
// [MAC1,MAC2,MAC3] = MAC+(FC-MAC)*IR0
// [MAC1,MAC2,MAC3] = [MAC1,MAC2,MAC3] SAR (sf*12)
// Color FIFO = [MAC1/16,MAC2/16,MAC3/16,CODE], [IR1,IR2,IR3] = [MAC1,MAC2,MAC3]
fn execute_dcpl(r: *GTERegisters.Typed, instruction: instructions.GTECommand) void {
    const mac1 = @shlExact(@as(i44, std.math.mulWide(i16, r.RGBC.r, r.IR1)), 4);
    const mac2 = @shlExact(@as(i44, std.math.mulWide(i16, r.RGBC.g, r.IR2)), 4);
    const mac3 = @shlExact(@as(i44, std.math.mulWide(i16, r.RGBC.b, r.IR3)), 4);

    execute_depth_cue_internal(r, .{ mac1, mac2, mac3 }, instruction.sf, instruction.lm);
}

// COP2 0E80413h - 19 Cycles - NCDS - Normal color depth cue (single vector)
fn execute_ncds(r: *GTERegisters.Typed, instruction: instructions.GTECommand) void {
    execute_ncd(r, instruction, &r.V0);
}

// COP2 0F80416h - 44 Cycles - NCDT - Normal color depth cue (triple vectors)
fn execute_ncdt(r: *GTERegisters.Typed, instruction: instructions.GTECommand) void {
    inline for (.{ &r.V0, &r.V1, &r.V2 }) |vector| {
        execute_ncd(r, instruction, vector);
    }
}

// In: V0=Normal vector (for triple variants repeated with V1 and V2), BK=Background color, RGBC=Primary color/code, LLM=Light matrix, LCM=Color matrix, IR0=Interpolation value.
//
//   [IR1,IR2,IR3] = [MAC1,MAC2,MAC3] = (LLM*V0) SAR (sf*12)
//   [IR1,IR2,IR3] = [MAC1,MAC2,MAC3] = (BK*1000h + LCM*IR) SAR (sf*12)
//   [MAC1,MAC2,MAC3] = [R*IR1,G*IR2,B*IR3] SHL 4          ;<--- for NCDx/NCCx
//   [MAC1,MAC2,MAC3] = MAC+(FC-MAC)*IR0                   ;<--- for NCDx only
//   [MAC1,MAC2,MAC3] = [MAC1,MAC2,MAC3] SAR (sf*12)       ;<--- for NCDx/NCCx
//   Color FIFO = [MAC1/16,MAC2/16,MAC3/16,CODE], [IR1,IR2,IR3] = [MAC1,MAC2,MAC3]
fn execute_ncd(r: *GTERegisters.Typed, instruction: instructions.GTECommand, vector: *GTERegisters.Vector) void {
    // LLM=Light matrix
    //   [IR1,IR2,IR3] = [MAC1,MAC2,MAC3] = (LLM*V0) SAR (sf*12)
    const zero_offset: i32_3 = .{ 0, 0, 0 };
    execute_mat_mul(r, &r.LLM, vector, zero_offset, instruction.sf, instruction.lm);

    const color_vector: GTERegisters.Vector = .{
        .x = r.IR1,
        .y = r.IR2,
        .z = r.IR3,
    };

    const color_offset: i32_3 = .{ r.RBK, r.GBK, r.BBK };
    execute_mat_mul(r, &r.LCM, &color_vector, color_offset, instruction.sf, instruction.lm);

    // RGBC=Primary color/code
    //   [MAC1,MAC2,MAC3] = [R*IR1,G*IR2,B*IR3] SHL 4          ;<--- for NCDx/NCCx
    // Q(27, 16)
    const mac1 = @shlExact(@as(i44, std.math.mulWide(i16, r.RGBC.r, r.IR1)), 4);
    const mac2 = @shlExact(@as(i44, std.math.mulWide(i16, r.RGBC.g, r.IR2)), 4);
    const mac3 = @shlExact(@as(i44, std.math.mulWide(i16, r.RGBC.b, r.IR3)), 4);

    execute_depth_cue_internal(r, .{ mac1, mac2, mac3 }, instruction.sf, instruction.lm);
}

// COP2 0980011h - 8 Cycles - INTPL - Interpolation of a vector and far color
//
// In: [IR1,IR2,IR3]=Vector, FC=Far Color, IR0=Interpolation value, CODE=MSB of RGBC, and, for DCPL, R,G,B=LSBs of RGBC.
//
// [MAC1,MAC2,MAC3] = [IR1,IR2,IR3] SHL 12               ;<--- for INTPL only
// [MAC1,MAC2,MAC3] = MAC+(FC-MAC)*IR0
// [MAC1,MAC2,MAC3] = [MAC1,MAC2,MAC3] SAR (sf*12)
// Color FIFO = [MAC1/16,MAC2/16,MAC3/16,CODE], [IR1,IR2,IR3] = [MAC1,MAC2,MAC3]
fn execute_intpl(r: *GTERegisters.Typed, instruction: instructions.GTECommand) void {
    const mac1 = @shlExact(@as(i44, r.IR1), 12);
    const mac2 = @shlExact(@as(i44, r.IR2), 12);
    const mac3 = @shlExact(@as(i44, r.IR3), 12);

    execute_depth_cue_internal(r, .{ mac1, mac2, mac3 }, instruction.sf, instruction.lm);
}

// COP2 0A00428h+sf*80000h - 5 Cycles - SQR(sf) - Square vector
//
// [MAC1,MAC2,MAC3] = [IR1*IR1,IR2*IR2,IR3*IR3] SHR (sf*12)
// [IR1,IR2,IR3]    = [MAC1,MAC2,MAC3]    ;IR1,IR2,IR3 saturated to max 7FFFh
//
// Calculates the square of a vector. The result is, of course, always positive,
// so the "lm" flag for negative saturation has no effect.
fn execute_sqr_sf(r: *GTERegisters.Typed, instruction: instructions.GTECommand) void {
    const mac1 = @as(i44, std.math.mulWide(i16, r.IR1, r.IR1));
    const mac2 = @as(i44, std.math.mulWide(i16, r.IR2, r.IR2));
    const mac3 = @as(i44, std.math.mulWide(i16, r.IR3, r.IR3));

    r.MAC1 = mac_sar12_raw(mac1, instruction.sf);
    r.MAC2 = mac_sar12_raw(mac2, instruction.sf);
    r.MAC3 = mac_sar12_raw(mac3, instruction.sf);

    r.IR1 = @intCast(std.math.clamp(r.MAC1, std.math.minInt(i16), std.math.maxInt(i16)));
    r.IR2 = @intCast(std.math.clamp(r.MAC2, std.math.minInt(i16), std.math.maxInt(i16)));
    r.IR3 = @intCast(std.math.clamp(r.MAC3, std.math.minInt(i16), std.math.maxInt(i16)));

    r.FLAG.ir1_saturated |= r.IR1 != r.MAC1;
    r.FLAG.ir2_saturated |= r.IR2 != r.MAC2;
    r.FLAG.ir3_saturated |= r.IR3 != r.MAC3;
}

// COP2 0C8041Eh - 14 Cycles - NCS - Normal color (single)
fn execute_ncs(r: *GTERegisters.Typed, instruction: instructions.GTECommand) void {
    execute_nc(r, &r.V0, instruction.sf, instruction.lm);
}

// COP2 0D80420h - 30 Cycles - NCT - Normal color (triple)
fn execute_nct(r: *GTERegisters.Typed, instruction: instructions.GTECommand) void {
    inline for (.{ &r.V0, &r.V1, &r.V2 }) |vector| {
        execute_nc(r, vector, instruction.sf, instruction.lm);
    }
}

fn execute_nc(r: *GTERegisters.Typed, vector: *GTERegisters.Vector, sf: bool, lm: bool) void {
    const zero_offset: i32_3 = .{ 0, 0, 0 };

    // [IR1,IR2,IR3] = [MAC1,MAC2,MAC3] = (LLM*V0) SAR (sf*12)
    execute_mat_mul(r, &r.LLM, vector, zero_offset, sf, lm);

    const color_vector: GTERegisters.Vector = .{
        .x = r.IR1,
        .y = r.IR2,
        .z = r.IR3,
    };

    const color_offset: i32_3 = .{ r.RBK, r.GBK, r.BBK };

    // [IR1,IR2,IR3] = [MAC1,MAC2,MAC3] = (BK*1000h + LCM*IR) SAR (sf*12)
    execute_mat_mul(r, &r.LCM, &color_vector, color_offset, sf, lm);

    // Color FIFO = [MAC1/16,MAC2/16,MAC3/16,CODE], [IR1,IR2,IR3] = [MAC1,MAC2,MAC3]
    const color: state.ColorRGB8Code = .{
        .r = @intCast(std.math.clamp(r.MAC1 >> 4, 0, std.math.maxInt(u8))),
        .g = @intCast(std.math.clamp(r.MAC2 >> 4, 0, std.math.maxInt(u8))),
        .b = @intCast(std.math.clamp(r.MAC3 >> 4, 0, std.math.maxInt(u8))),
        .code = r.RGBC.code,
    };

    r.FLAG.color_r_saturated |= color.r != r.MAC1 >> 4;
    r.FLAG.color_g_saturated |= color.g != r.MAC2 >> 4;
    r.FLAG.color_b_saturated |= color.b != r.MAC3 >> 4;

    push_color_fifo(r, color);
}

// COP2 0780010h - 8 Cycles - DPCS - Depth Cueing (single)
fn execute_dpcs(r: *GTERegisters.Typed, instruction: instructions.GTECommand) void {
    execute_dpc(r, instruction, r.RGBC);
}

// COP2 0F8002Ah - 17 Cycles - DPCT - Depth Cueing (triple)
fn execute_dpct(r: *GTERegisters.Typed, instruction: instructions.GTECommand) void {
    inline for (0..3) |_| {
        execute_dpc(r, instruction, r.RGB0);
    }
}

// In: [IR1,IR2,IR3]=Vector, FC=Far Color, IR0=Interpolation value, CODE=MSB of RGBC, and, for DCPL, R,G,B=LSBs of RGBC.
//
//   [MAC1,MAC2,MAC3] = [R,G,B] SHL 16                     ;<--- for DPCS/DPCT
//   [MAC1,MAC2,MAC3] = MAC+(FC-MAC)*IR0
//   [MAC1,MAC2,MAC3] = [MAC1,MAC2,MAC3] SAR (sf*12)
//   Color FIFO = [MAC1/16,MAC2/16,MAC3/16,CODE], [IR1,IR2,IR3] = [MAC1,MAC2,MAC3]
//
// DPCT executes thrice, and reads the R,G,B values from RGB0 (ie. reads from the Bottom of the Color FIFO, instead of from the RGBC register) (the CODE value is kept read from RGBC as usually), so, after DPCT execution, the RGB0,RGB1,RGB2 Fifo entries are modified.
fn execute_dpc(r: *GTERegisters.Typed, instruction: instructions.GTECommand, input_color: state.ColorRGB8Code) void {
    // [MAC1,MAC2,MAC3] = [R,G,B] SHL 16
    const mac1 = @shlExact(@as(i44, input_color.r), 16);
    const mac2 = @shlExact(@as(i44, input_color.g), 16);
    const mac3 = @shlExact(@as(i44, input_color.b), 16);

    execute_depth_cue_internal(r, .{ mac1, mac2, mac3 }, instruction.sf, instruction.lm);
}

// [MAC1,MAC2,MAC3] = (([IR1,IR2,IR3] * IR0) + [MAC1,MAC2,MAC3])
// [MAC1,MAC2,MAC3] = [MAC1,MAC2,MAC3] SAR (sf*12)
// Color FIFO = [MAC1/16,MAC2/16,MAC3/16,CODE], [IR1,IR2,IR3] = [MAC1,MAC2,MAC3]
fn execute_depth_cue_internal(r: *GTERegisters.Typed, macn: i44_3, sf: bool, lm: bool) void {
    var mac1_overflow: u1 = undefined;
    var mac2_overflow: u1 = undefined;
    var mac3_overflow: u1 = undefined;

    var mac1, mac1_overflow = @subWithOverflow(@shlExact(@as(i44, r.RFC), 12), macn[0]);
    var mac2, mac2_overflow = @subWithOverflow(@shlExact(@as(i44, r.GFC), 12), macn[1]);
    var mac3, mac3_overflow = @subWithOverflow(@shlExact(@as(i44, r.BFC), 12), macn[2]);

    r.FLAG.mac1_wrapped_negative |= if (mac1_overflow != 0) mac1 > 0 else false;
    r.FLAG.mac1_wrapped_positive |= if (mac1_overflow != 0) mac1 < 0 else false;
    r.FLAG.mac2_wrapped_negative |= if (mac2_overflow != 0) mac2 > 0 else false;
    r.FLAG.mac2_wrapped_positive |= if (mac2_overflow != 0) mac2 < 0 else false;
    r.FLAG.mac3_wrapped_negative |= if (mac3_overflow != 0) mac3 > 0 else false;
    r.FLAG.mac3_wrapped_positive |= if (mac3_overflow != 0) mac3 < 0 else false;

    r.MAC1 = mac_sar12_raw(mac1, sf);
    r.MAC2 = mac_sar12_raw(mac2, sf);
    r.MAC3 = mac_sar12_raw(mac3, sf);

    r.IR1 = @intCast(std.math.clamp(r.MAC1, std.math.minInt(i16), std.math.maxInt(i16)));
    r.IR2 = @intCast(std.math.clamp(r.MAC2, std.math.minInt(i16), std.math.maxInt(i16)));
    r.IR3 = @intCast(std.math.clamp(r.MAC3, std.math.minInt(i16), std.math.maxInt(i16)));

    r.FLAG.ir1_saturated |= r.IR1 != r.MAC1;
    r.FLAG.ir2_saturated |= r.IR2 != r.MAC2;
    r.FLAG.ir3_saturated |= r.IR3 != r.MAC3;

    mac1, mac1_overflow = @addWithOverflow(std.math.mulWide(i16, r.IR1, r.IR0), macn[0]);
    mac2, mac2_overflow = @addWithOverflow(std.math.mulWide(i16, r.IR2, r.IR0), macn[1]);
    mac3, mac3_overflow = @addWithOverflow(std.math.mulWide(i16, r.IR3, r.IR0), macn[2]);

    r.FLAG.mac1_wrapped_negative |= if (mac1_overflow != 0) mac1 > 0 else false;
    r.FLAG.mac1_wrapped_positive |= if (mac1_overflow != 0) mac1 < 0 else false;
    r.FLAG.mac2_wrapped_negative |= if (mac2_overflow != 0) mac2 > 0 else false;
    r.FLAG.mac2_wrapped_positive |= if (mac2_overflow != 0) mac2 < 0 else false;
    r.FLAG.mac3_wrapped_negative |= if (mac3_overflow != 0) mac3 > 0 else false;
    r.FLAG.mac3_wrapped_positive |= if (mac3_overflow != 0) mac3 < 0 else false;

    r.MAC1 = mac_sar12_raw(mac1, sf);
    r.MAC2 = mac_sar12_raw(mac2, sf);
    r.MAC3 = mac_sar12_raw(mac3, sf);

    execute_ir_push_color(r, lm);
}

fn execute_ir_push_color(r: *GTERegisters.Typed, lm: bool) void {
    const ir_lm_min: i16 = if (lm) 0 else std.math.minInt(i16);

    r.IR1 = @intCast(std.math.clamp(r.MAC1, ir_lm_min, std.math.maxInt(i16)));
    r.IR2 = @intCast(std.math.clamp(r.MAC2, ir_lm_min, std.math.maxInt(i16)));
    r.IR3 = @intCast(std.math.clamp(r.MAC3, ir_lm_min, std.math.maxInt(i16)));

    r.FLAG.ir1_saturated |= r.IR1 != r.MAC1;
    r.FLAG.ir2_saturated |= r.IR2 != r.MAC2;
    r.FLAG.ir3_saturated |= r.IR3 != r.MAC3;

    // Color FIFO = [MAC1/16,MAC2/16,MAC3/16,CODE], [IR1,IR2,IR3] = [MAC1,MAC2,MAC3]
    const color: state.ColorRGB8Code = .{
        .r = @intCast(std.math.clamp(r.MAC1 >> 4, 0, std.math.maxInt(u8))),
        .g = @intCast(std.math.clamp(r.MAC2 >> 4, 0, std.math.maxInt(u8))),
        .b = @intCast(std.math.clamp(r.MAC3 >> 4, 0, std.math.maxInt(u8))),
        .code = r.RGBC.code,
    };

    r.FLAG.color_r_saturated |= color.r != r.MAC1 >> 4;
    r.FLAG.color_g_saturated |= color.g != r.MAC2 >> 4;
    r.FLAG.color_b_saturated |= color.b != r.MAC3 >> 4;

    push_color_fifo(r, color);
}

// COP2 108041Bh - 17 Cycles - NCCS - Normal Color Color (single vector)
fn execute_nccs(r: *GTERegisters.Typed, instruction: instructions.GTECommand) void {
    execute_ncc(r, &r.V0, instruction.sf, instruction.lm);
}

// COP2 118043Fh - 39 Cycles - NCCT - Normal Color Color (triple vector)
fn execute_ncct(r: *GTERegisters.Typed, instruction: instructions.GTECommand) void {
    inline for (.{ &r.V0, &r.V1, &r.V2 }) |vector| {
        execute_ncc(r, vector, instruction.sf, instruction.lm);
    }
}

// In: V0=Normal vector (for triple variants repeated with V1 and V2), BK=Background color, RGBC=Primary color/code, LLM=Light matrix, LCM=Color matrix, IR0=Interpolation value.
//
fn execute_ncc(r: *GTERegisters.Typed, vector: *GTERegisters.Vector, sf: bool, lm: bool) void {
    // [IR1,IR2,IR3] = [MAC1,MAC2,MAC3] = (LLM*V0) SAR (sf*12)
    const zero_offset: i32_3 = .{ 0, 0, 0 };
    execute_mat_mul(r, &r.LLM, vector, zero_offset, sf, lm);

    const color_vector: GTERegisters.Vector = .{
        .x = r.IR1,
        .y = r.IR2,
        .z = r.IR3,
    };

    const color_offset: i32_3 = .{ r.RBK, r.GBK, r.BBK };

    // [IR1,IR2,IR3] = [MAC1,MAC2,MAC3] = (BK*1000h + LCM*IR) SAR (sf*12)
    execute_mat_mul(r, &r.LCM, &color_vector, color_offset, sf, lm);

    // [MAC1,MAC2,MAC3] = [R*IR1,G*IR2,B*IR3] SHL 4          ;<--- for NCDx/NCCx
    // Q(27, 16)
    const mac1 = @shlExact(@as(i44, std.math.mulWide(i16, r.RGBC.r, r.IR1)), 4);
    const mac2 = @shlExact(@as(i44, std.math.mulWide(i16, r.RGBC.g, r.IR2)), 4);
    const mac3 = @shlExact(@as(i44, std.math.mulWide(i16, r.RGBC.b, r.IR3)), 4);

    r.MAC1 = mac_sar12_raw(mac1, sf);
    r.MAC2 = mac_sar12_raw(mac2, sf);
    r.MAC3 = mac_sar12_raw(mac3, sf);

    execute_ir_push_color(r, lm);
}

// COP2 138041Ch - 11 Cycles - CC(lm=1) - Color Color
// COP2 1280414h - 13 Cycles - CDP(...) - Color Depth Que
//
// In: [IR1,IR2,IR3]=Vector, RGBC=Primary color/code, LCM=Color matrix, BK=Background color, and, for CDP, IR0=Interpolation value, FC=Far color.
//
//   [IR1,IR2,IR3] = [MAC1,MAC2,MAC3] = (BK*1000h + LCM*IR) SAR (sf*12)
//   [MAC1,MAC2,MAC3] = [R*IR1,G*IR2,B*IR3] SHL 4
//   [MAC1,MAC2,MAC3] = MAC+(FC-MAC)*IR0                   ;<--- for CDP only
//   [MAC1,MAC2,MAC3] = [MAC1,MAC2,MAC3] SAR (sf*12)
//   Color FIFO = [MAC1/16,MAC2/16,MAC3/16,CODE], [IR1,IR2,IR3] = [MAC1,MAC2,MAC3]
fn execute_cdp(r: *GTERegisters.Typed, instruction: instructions.GTECommand) void {
    const color_vector: GTERegisters.Vector = .{
        .x = r.IR1,
        .y = r.IR2,
        .z = r.IR3,
    };

    const color_offset: i32_3 = .{ r.RBK, r.GBK, r.BBK };
    execute_mat_mul(r, &r.LCM, &color_vector, color_offset, instruction.sf, instruction.lm);

    // Q(27, 16)
    const mac1 = @shlExact(@as(i44, std.math.mulWide(i16, r.RGBC.r, r.IR1)), 4);
    const mac2 = @shlExact(@as(i44, std.math.mulWide(i16, r.RGBC.g, r.IR2)), 4);
    const mac3 = @shlExact(@as(i44, std.math.mulWide(i16, r.RGBC.b, r.IR3)), 4);

    execute_depth_cue_internal(r, .{ mac1, mac2, mac3 }, instruction.sf, instruction.lm);
}

fn execute_cc(r: *GTERegisters.Typed, instruction: instructions.GTECommand) void {
    const color_vector: GTERegisters.Vector = .{
        .x = r.IR1,
        .y = r.IR2,
        .z = r.IR3,
    };

    const color_offset: i32_3 = .{ r.RBK, r.GBK, r.BBK };
    execute_mat_mul(r, &r.LCM, &color_vector, color_offset, instruction.sf, instruction.lm);

    // Q(27, 16)
    const mac1 = @shlExact(@as(i44, std.math.mulWide(i16, r.RGBC.r, r.IR1)), 4);
    const mac2 = @shlExact(@as(i44, std.math.mulWide(i16, r.RGBC.g, r.IR2)), 4);
    const mac3 = @shlExact(@as(i44, std.math.mulWide(i16, r.RGBC.b, r.IR3)), 4);

    r.MAC1 = mac_sar12_raw(mac1, instruction.sf);
    r.MAC2 = mac_sar12_raw(mac2, instruction.sf);
    r.MAC3 = mac_sar12_raw(mac3, instruction.sf);

    execute_ir_push_color(r, instruction.lm);
}

// COP2 1400006h - 8 Cycles - NCLIP - Normal clipping
//
//   MAC0 =   SX0*SY1 + SX1*SY2 + SX2*SY0 - SX0*SY2 - SX1*SY0 - SX2*SY1
//
// The sign of the result indicates whether the polygon coordinates are arranged clockwise or anticlockwise
// (ie. whether the front side or backside is visible). If the result is zero, then it's neither one
// (ie. the vertices are all arranged in a straight line).
// Note: The GPU probably renders straight lines as invisble 0 pixel width lines?
fn execute_nclip(r: *GTERegisters.Typed, _: instructions.GTECommand) void {
    var mac0: i44 = 0;

    mac0 += std.math.mulWide(i16, r.S0.x, r.S1.y);
    mac0 += std.math.mulWide(i16, r.S1.x, r.S2.y);
    mac0 += std.math.mulWide(i16, r.S2.x, r.S0.y);

    mac0 -= std.math.mulWide(i16, r.S0.x, r.S2.y);
    mac0 -= std.math.mulWide(i16, r.S1.x, r.S0.y);
    mac0 -= std.math.mulWide(i16, r.S2.x, r.S1.y);

    r.MAC0 = @truncate(mac0);
    r.FLAG.mac0_wrapped_positive |= mac0 > std.math.maxInt(i32);
    r.FLAG.mac0_wrapped_negative |= mac0 < std.math.minInt(i32);
}

// COP2 158002Dh - 5 Cycles - AVSZ3 - Average of three Z values (for Triangles)
// COP2 168002Eh - 6 Cycles - AVSZ4 - Average of four Z values (for Quads)
//
//   MAC0 =  ZSF3*(SZ1+SZ2+SZ3)       ;for AVSZ3
//   MAC0 =  ZSF4*(SZ0+SZ1+SZ2+SZ3)   ;for AVSZ4
//   OTZ  =  MAC0/1000h               ;for both (saturated to 0..FFFFh)
//
// Adds three or four Z values together and multplies them by a fixed point value.
// The result can be used as index in the GPU's Ordering Table (OT).
//
// GPU Depth Ordering
// The scaling factors would be usually ZSF3=N/30h and ZSF4=N/40h, where "N" is the number of entries in the OT (max 10000h).
// SZn and OTZ are unsigned 16bit values, for whatever reason ZSFn registers are signed 16bit values
// (negative values would allow a negative result in MAC0, but would saturate OTZ to zero).
const AVSZMode = enum {
    AVSZ3,
    AVSZ4,
};

fn execute_avsz(r: *GTERegisters.Typed, mode: AVSZMode) void {
    var mac0: i44 = 0;

    switch (mode) {
        .AVSZ3 => {
            mac0 += r.SZ1;
            mac0 += r.SZ2;
            mac0 += r.SZ3;

            mac0 *= r.ZSF3;
        },
        .AVSZ4 => {
            mac0 += r.SZ0;
            mac0 += r.SZ1;
            mac0 += r.SZ2;
            mac0 += r.SZ3;

            mac0 *= r.ZSF4;
        },
    }

    r.MAC0 = @truncate(mac0);
    r.FLAG.mac0_wrapped_negative |= mac0 < std.math.minInt(i32);
    r.FLAG.mac0_wrapped_positive |= mac0 > std.math.maxInt(i32);

    const sz = mac0 >> 12;

    r.OTZ = @intCast(std.math.clamp(sz, 0, std.math.maxInt(u16)));
    r.FLAG.sz_saturated |= r.OTZ != sz;
}

// COP2 170000Ch+sf*80000h - 6 Cycles - OP(sf,lm) - Cross product of 2 vectors
//
//   [MAC1,MAC2,MAC3] = [IR3*D2-IR2*D3, IR1*D3-IR3*D1, IR2*D1-IR1*D2] SAR (sf*12)
//   [IR1,IR2,IR3]    = [MAC1,MAC2,MAC3]                        ;copy result
//
// Calculates the cross product of two signed 16bit vectors. Note: D1,D2,D3 are meant to be the RT11,RT22,RT33 elements of the RT matrix "misused" as vector. lm should be usually zero.
// The official Sony documentation refers to this opcode as the Outer Product, but this is likely the result of a bad translation from Japanese: "外積 - gaiseki" can be translated to "cross product", "vector product", or "outer product".
fn execute_op_sf(r: *GTERegisters.Typed, instruction: instructions.GTECommand) void {
    // Q(19, 12)
    const mac1 = @as(i44, std.math.mulWide(i16, r.RT.m22, r.IR3)) - std.math.mulWide(i16, r.RT.m33, r.IR2);
    const mac2 = @as(i44, std.math.mulWide(i16, r.RT.m33, r.IR1)) - std.math.mulWide(i16, r.RT.m11, r.IR3);
    const mac3 = @as(i44, std.math.mulWide(i16, r.RT.m11, r.IR2)) - std.math.mulWide(i16, r.RT.m22, r.IR1);

    r.MAC1 = mac_sar12_raw(mac1, instruction.sf);
    r.MAC2 = mac_sar12_raw(mac2, instruction.sf);
    r.MAC3 = mac_sar12_raw(mac3, instruction.sf);

    const ir_lm_min: i16 = if (instruction.lm) 0 else std.math.minInt(i16);

    r.IR1 = @intCast(std.math.clamp(r.MAC1, ir_lm_min, std.math.maxInt(i16)));
    r.IR2 = @intCast(std.math.clamp(r.MAC2, ir_lm_min, std.math.maxInt(i16)));
    r.IR3 = @intCast(std.math.clamp(r.MAC3, ir_lm_min, std.math.maxInt(i16)));

    r.FLAG.ir1_saturated |= r.IR1 != r.MAC1;
    r.FLAG.ir2_saturated |= r.IR2 != r.MAC2;
    r.FLAG.ir3_saturated |= r.IR3 != r.MAC3;
}

// COP2 190003Dh - 5 Cycles - GPF(sf,lm) - General purpose Interpolation
fn execute_gpf_sf(r: *GTERegisters.Typed, instruction: instructions.GTECommand) void {
    // [MAC1,MAC2,MAC3] = [0,0,0]
    execute_gp(r, .{ 0, 0, 0 }, instruction.sf, instruction.lm);
}

// COP2 1A0003Eh - 5 Cycles - GPL(sf,lm) - General Interpolation with base
fn execute_gpl_sf(r: *GTERegisters.Typed, instruction: instructions.GTECommand) void {
    // [MAC1,MAC2,MAC3] = [MAC1,MAC2,MAC3] SHL (sf*12)
    const mac1 = if (instruction.sf) @shlExact(@as(i44, r.MAC1), 12) else @as(i44, r.MAC1);
    const mac2 = if (instruction.sf) @shlExact(@as(i44, r.MAC2), 12) else @as(i44, r.MAC2);
    const mac3 = if (instruction.sf) @shlExact(@as(i44, r.MAC3), 12) else @as(i44, r.MAC3);

    execute_gp(r, .{ mac1, mac2, mac3 }, instruction.sf, instruction.lm);
}

fn execute_gp(r: *GTERegisters.Typed, macn: i44_3, sf: bool, lm: bool) void {
    // [MAC1,MAC2,MAC3] = (([IR1,IR2,IR3] * IR0) + [MAC1,MAC2,MAC3]) SAR (sf*12)
    const mac1, const mac1_overflow = @addWithOverflow(std.math.mulWide(i16, r.IR1, r.IR0), macn[0]);
    const mac2, const mac2_overflow = @addWithOverflow(std.math.mulWide(i16, r.IR2, r.IR0), macn[1]);
    const mac3, const mac3_overflow = @addWithOverflow(std.math.mulWide(i16, r.IR3, r.IR0), macn[2]);

    r.FLAG.mac1_wrapped_negative |= if (mac1_overflow != 0) mac1 > 0 else false;
    r.FLAG.mac1_wrapped_positive |= if (mac1_overflow != 0) mac1 < 0 else false;
    r.FLAG.mac2_wrapped_negative |= if (mac2_overflow != 0) mac2 > 0 else false;
    r.FLAG.mac2_wrapped_positive |= if (mac2_overflow != 0) mac2 < 0 else false;
    r.FLAG.mac3_wrapped_negative |= if (mac3_overflow != 0) mac3 > 0 else false;
    r.FLAG.mac3_wrapped_positive |= if (mac3_overflow != 0) mac3 < 0 else false;

    r.MAC1 = mac_sar12_raw(mac1, sf);
    r.MAC2 = mac_sar12_raw(mac2, sf);
    r.MAC3 = mac_sar12_raw(mac3, sf);

    execute_ir_push_color(r, lm);
}

fn push_position_xy_fifo(r: *GTERegisters.Typed, pos: GTERegisters.PosType) void {
    r.S0 = r.S1;
    r.S1 = r.S2;
    r.S2 = pos;
    r.SP = pos;
}

fn push_position_z_fifo(r: *GTERegisters.Typed, z: u16) void {
    r.SZ0 = r.SZ1;
    r.SZ1 = r.SZ2;
    r.SZ2 = r.SZ3;
    r.SZ3 = z;
}

fn push_color_fifo(r: *GTERegisters.Typed, color: state.ColorRGB8Code) void {
    r.RGB0 = r.RGB1;
    r.RGB1 = r.RGB2;
    r.RGB2 = color;
}

inline fn mac_sar12_raw(raw: i44, sf: bool) i32 {
    return if (sf) @intCast(raw >> 12) else @truncate(raw);
}
