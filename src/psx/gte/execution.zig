const std = @import("std");

const config = @import("../config.zig");
const state = @import("state.zig");
const instructions = @import("instructions.zig");
const GTERegisters = state.GTERegisters;
const Q = @import("fixed_point.zig").Q;
const PSXState = @import("../state.zig").PSXState;

pub fn load_data_reg(regs: *const GTERegisters, register: GTERegisters.DataRegister) u32 {
    std.debug.print("GTE data load {}\n", .{register});

    // FIXME handle u16 masking and sign-extension
    return switch (register) {
        .SXP_SYP => @panic("Unimplemented"),
        .IRGB, .ORGB => @panic("Unimplemented"),
        else => regs.raw.data[@backingInt(register)],
    };
}

// We don't truncate when registers only have 16 bit values.
// Just make sure the unused bits don't get read.
pub fn store_data_reg(regs: *GTERegisters, register: GTERegisters.DataRegister, value: u32) void {
    std.debug.print("GTE data store {} with {x}\n", .{ register, value });

    switch (register) {
        .SXP_SYP => @panic("Unimplemented"),
        .IRGB => @panic("Unimplemented"),
        .ORGB => @panic("Unimplemented"),
        .LZCR => @panic("Unimplemented"),
        else => regs.raw.data[@backingInt(register)] = value,
    }
}

pub fn load_ctrl_reg(regs: *const GTERegisters, register: GTERegisters.CtrlRegister) u32 {
    std.debug.print("GTE ctrl load {}\n", .{register});

    return switch (register) {
        .FLAG => regs.raw.ctrl[@backingInt(register)],
        else => @panic("Unimplemented"),
        // else => self.regs.ctrl.raw[@backingInt(register)],
    };
}

// We don't truncate when registers only have 16 bit values.
// Just make sure the unused bits don't get read.
pub fn store_ctrl_reg(regs: *GTERegisters, register: GTERegisters.CtrlRegister, value: u32) void {
    std.debug.print("GTE ctrl store {} with {x}\n", .{ register, value });

    switch (register) {
        .FLAG => {
            const flag_save = regs.typed.FLAG;

            regs.raw.ctrl[@backingInt(register)] = value;

            regs.typed.FLAG.unused_b0_11 = 0;
            regs.typed.FLAG._b31 = flag_save._b31;
        },
        else => regs.raw.ctrl[@backingInt(register)] = value,
    }
}

pub fn execute(psx: *PSXState, instruction: instructions.GTECommand) void {
    std.debug.print("GTE instruction {}\n", .{instruction});

    psx.gte.regs.typed.FLAG = .{};

    switch (instruction.opcode) {
        .RTPS => execute_rtps(psx, instruction),
        .RTPT => execute_rtpt(psx, instruction),
        .MVMVA => execute_mvmva(psx, instruction),
        .DCPL => execute_dcpl(psx, instruction),
        .DPCS => execute_dpcs(psx, instruction),
        .DPCT => execute_dpct(psx, instruction),
        .INTPL => execute_intpl(psx, instruction),
        .SQR_sf => execute_sqr_sf(psx, instruction),
        .NCS => execute_ncs(psx, instruction),
        .NCT => execute_nct(psx, instruction),
        .NCDS => execute_ncds(psx, instruction),
        .NCDT => execute_ncdt(psx, instruction),
        .NCCS => execute_nccs(psx, instruction),
        .NCCT => execute_ncct(psx, instruction),
        .CDP => execute_cdp(psx, instruction),
        .CC => execute_cc(psx, instruction),
        .NCLIP => execute_nclip(psx, instruction),
        .AVSZ3 => execute_avsz3(psx, instruction),
        .AVSZ4 => execute_avsz4(psx, instruction),
        .OP_sf => execute_op_sf(psx, instruction),
        .GPF_sf => execute_gpf_sf(psx, instruction),
        .GPL_sf => execute_gpl_sf(psx, instruction),
        _ => @panic("Invalid GTE instruction"),
    }
}

fn execute_rtps(psx: *PSXState, instruction: instructions.GTECommand) void {
    const r = &psx.gte.regs.typed;

    execute_rtp(psx, instruction, &r.V0);
}

fn execute_rtpt(psx: *PSXState, instruction: instructions.GTECommand) void {
    const r = &psx.gte.regs.typed;

    inline for (.{ &r.V0, &r.V1, &r.V2 }) |vector| {
        execute_rtp(psx, instruction, vector);
    }
}

fn execute_rtp(psx: *PSXState, instruction: instructions.GTECommand, vector: *GTERegisters.Vector) void {
    const r = &psx.gte.regs.typed;

    std.debug.print("Regs: {}\n", .{r});

    // FIXME Executive decision here to not worry about setting correct overflow flags yet.
    // IR1 = MAC1 = (TRX*1000h + RT11*VX0 + RT12*VY0 + RT13*VZ0) SAR (sf*12)
    // IR2 = MAC2 = (TRY*1000h + RT21*VX0 + RT22*VY0 + RT23*VZ0) SAR (sf*12)
    // IR3 = MAC3 = (TRZ*1000h + RT31*VX0 + RT32*VY0 + RT33*VZ0) SAR (sf*12)
    // SZ3 = MAC3 SAR ((1-sf)*12)                           ;ScreenZ FIFO 0..+FFFFh
    var r1: Q(31, 12) = r.TRX.lift(12);
    var r2: Q(31, 12) = r.TRY.lift(12);
    var r3: Q(31, 12) = r.TRZ.lift(12);

    r1 = r1.add(r.RT11.mul(vector.x.as_q15f0).widen(Q(31, 12)));
    r2 = r2.add(r.RT21.mul(vector.x.as_q15f0).widen(Q(31, 12)));
    r3 = r3.add(r.RT31.mul(vector.x.as_q15f0).widen(Q(31, 12)));

    r1 = r1.add(r.RT12.mul(vector.y.as_q15f0).widen(Q(31, 12)));
    r2 = r2.add(r.RT22.mul(vector.y.as_q15f0).widen(Q(31, 12)));
    r3 = r3.add(r.RT32.mul(vector.y.as_q15f0).widen(Q(31, 12)));

    r1 = r1.add(r.RT13.mul(vector.z.as_q15f0).widen(Q(31, 12)));
    r2 = r2.add(r.RT23.mul(vector.z.as_q15f0).widen(Q(31, 12)));
    r3 = r3.add(r.RT33.mul(vector.z.as_q15f0).widen(Q(31, 12)));

    // FIXME
    const z: u16 = @intCast(std.math.clamp(r3.backing_value >> 12, 0, 0xffff));

    push_position_z_fifo(&psx.gte.regs, z);

    // FIXME
    r.MAC1.as_q31f0 = .init(mac_sar12(r1, instruction.sf));
    r.MAC2.as_q31f0 = .init(mac_sar12(r2, instruction.sf));
    r.MAC3.as_q31f0 = .init(mac_sar12(r3, instruction.sf));

    r.IR1.as_q15f0 = r.MAC1.as_q31f0.truncate(Q(15, 0));
    r.IR2.as_q15f0 = r.MAC2.as_q31f0.truncate(Q(15, 0));
    r.IR3.as_q15f0 = r.MAC3.as_q31f0.truncate(Q(15, 0));

    // MAC0=(((H*20000h/SZ3)+1)/2)*IR1+OFX, SX2=MAC0/10000h ;ScrX FIFO -400h..+3FFh
    // MAC0=(((H*20000h/SZ3)+1)/2)*IR2+OFY, SY2=MAC0/10000h ;ScrY FIFO -400h..+3FFh
    // MAC0=(((H*20000h/SZ3)+1)/2)*DQA+DQB, IR0=MAC0/1000h  ;Depth cueing 0..+1000h
    const div_overflow = r.H >= @as(u17, r.SZ3) * 2;
    const div = if (!div_overflow) @as(i64, (((@as(u32, r.H) << 17) / r.SZ3) + 1) >> 1) else 0x1_ff_ff;
    const div_q = Q(11, 16).init(@intCast(div));

    const rx: Q(27, 16) = div_q.mul(r.IR1.as_q15f0).add(r.OFX.widen(Q(27, 16)));
    const ry: Q(27, 16) = div_q.mul(r.IR2.as_q15f0).add(r.OFY.widen(Q(27, 16)));
    const rz: Q(19, 24) = div_q.mul(r.DQA).add(r.DQB.widen(Q(19, 24)));

    r.MAC0 = @truncate(rx.backing_value); // FIXME
    const sx: i16 = @truncate(r.MAC0 >> 16); // FIXME

    r.MAC0 = @truncate(ry.backing_value); // FIXME
    const sy: i16 = @truncate(r.MAC0 >> 16); // FIXME

    r.MAC0 = @truncate(rz.backing_value); // FIXME
    r.IR0 = .init(@truncate(r.MAC0 >> 12)); // FIXME

    r.FLAG.div_overflow = div_overflow; // FIXME

    push_position_xy_fifo(&psx.gte.regs, .{ .x = sx, .y = sy });
}

fn execute_mvmva(psx: *PSXState, instruction: instructions.GTECommand) void {
    _ = psx;
    _ = instruction;
    @panic("Unimplemented");
}

fn execute_dcpl(psx: *PSXState, instruction: instructions.GTECommand) void {
    _ = psx;
    _ = instruction;
    @panic("Unimplemented");
}

fn execute_dpcs(psx: *PSXState, instruction: instructions.GTECommand) void {
    _ = psx;
    _ = instruction;
    @panic("Unimplemented");
}

fn execute_dpct(psx: *PSXState, instruction: instructions.GTECommand) void {
    _ = psx;
    _ = instruction;
    @panic("Unimplemented");
}

fn execute_intpl(psx: *PSXState, instruction: instructions.GTECommand) void {
    _ = psx;
    _ = instruction;
    @panic("Unimplemented");
}

fn execute_sqr_sf(psx: *PSXState, instruction: instructions.GTECommand) void {
    _ = psx;
    _ = instruction;
    @panic("Unimplemented");
}

fn execute_ncs(psx: *PSXState, instruction: instructions.GTECommand) void {
    _ = psx;
    _ = instruction;
    @panic("Unimplemented");
}

fn execute_nct(psx: *PSXState, instruction: instructions.GTECommand) void {
    _ = psx;
    _ = instruction;
    @panic("Unimplemented");
}

// COP2 0E80413h - 19 Cycles - NCDS - Normal color depth cue (single vector)
// COP2 0F80416h - 44 Cycles - NCDT - Normal color depth cue (triple vectors)
//
// In: V0=Normal vector (for triple variants repeated with V1 and V2),
fn execute_ncds(psx: *PSXState, instruction: instructions.GTECommand) void {
    const r = &psx.gte.regs.typed;

    execute_ncd(psx, instruction, &r.V0);
}

fn execute_ncdt(psx: *PSXState, instruction: instructions.GTECommand) void {
    const r = &psx.gte.regs.typed;

    inline for (.{ &r.V0, &r.V1, &r.V2 }) |vector| {
        execute_ncd(psx, instruction, vector);
    }
}

fn execute_ncd(psx: *PSXState, instruction: instructions.GTECommand, vector: *GTERegisters.Vector) void {
    const r = &psx.gte.regs.typed;

    // LLM=Light matrix
    //   [IR1,IR2,IR3] = [MAC1,MAC2,MAC3] = (LLM*V0) SAR (sf*12)
    var l1: Q(19, 24) = r.L11.mul(vector.x.as_q3f12).widen(Q(19, 24));
    var l2: Q(19, 24) = r.L21.mul(vector.x.as_q3f12).widen(Q(19, 24));
    var l3: Q(19, 24) = r.L31.mul(vector.x.as_q3f12).widen(Q(19, 24));

    l1 = l1.add(r.L12.mul(vector.y.as_q3f12).widen(Q(19, 24)));
    l2 = l2.add(r.L22.mul(vector.y.as_q3f12).widen(Q(19, 24)));
    l3 = l3.add(r.L32.mul(vector.y.as_q3f12).widen(Q(19, 24)));

    l1 = l1.add(r.L13.mul(vector.z.as_q3f12).widen(Q(19, 24)));
    l2 = l2.add(r.L23.mul(vector.z.as_q3f12).widen(Q(19, 24)));
    l3 = l3.add(r.L33.mul(vector.z.as_q3f12).widen(Q(19, 24)));

    // FIXME
    r.MAC1.as_q19f12 = .init(mac_sar12(l1, instruction.sf));
    r.MAC2.as_q19f12 = .init(mac_sar12(l2, instruction.sf));
    r.MAC3.as_q19f12 = .init(mac_sar12(l3, instruction.sf));

    r.IR1.as_q3f12 = r.MAC1.as_q19f12.truncate(Q(3, 12));
    r.IR2.as_q3f12 = r.MAC2.as_q19f12.truncate(Q(3, 12));
    r.IR3.as_q3f12 = r.MAC3.as_q19f12.truncate(Q(3, 12));

    // BK=Background color
    // LCM=Color matrix
    //   [IR1,IR2,IR3] = [MAC1,MAC2,MAC3] = (BK*1000h + LCM*IR) SAR (sf*12)
    var c1: Q(19, 24) = r.RBK.lift(12);
    var c2: Q(19, 24) = r.GBK.lift(12);
    var c3: Q(19, 24) = r.BBK.lift(12);

    c1 = c1.add(r.LR1.mul(r.IR1.as_q3f12).widen(Q(19, 24)));
    c2 = c2.add(r.LG1.mul(r.IR1.as_q3f12).widen(Q(19, 24)));
    c3 = c3.add(r.LB1.mul(r.IR1.as_q3f12).widen(Q(19, 24)));

    c1 = c1.add(r.LR2.mul(r.IR2.as_q3f12).widen(Q(19, 24)));
    c2 = c2.add(r.LG2.mul(r.IR2.as_q3f12).widen(Q(19, 24)));
    c3 = c3.add(r.LB2.mul(r.IR2.as_q3f12).widen(Q(19, 24)));

    c1 = c1.add(r.LR3.mul(r.IR3.as_q3f12).widen(Q(19, 24)));
    c2 = c2.add(r.LG3.mul(r.IR3.as_q3f12).widen(Q(19, 24)));
    c3 = c3.add(r.LB3.mul(r.IR3.as_q3f12).widen(Q(19, 24)));

    // FIXME
    r.MAC1.as_q19f12 = .init(mac_sar12(c1, instruction.sf));
    r.MAC2.as_q19f12 = .init(mac_sar12(c2, instruction.sf));
    r.MAC3.as_q19f12 = .init(mac_sar12(c3, instruction.sf));

    r.IR1.as_q3f12 = r.MAC1.as_q19f12.truncate(Q(3, 12));
    r.IR2.as_q3f12 = r.MAC2.as_q19f12.truncate(Q(3, 12));
    r.IR3.as_q3f12 = r.MAC3.as_q19f12.truncate(Q(3, 12));

    // RGBC=Primary color/code
    //   [MAC1,MAC2,MAC3] = [R*IR1,G*IR2,B*IR3] SHL 4          ;<--- for NCDx/NCCx
    const step_a1: Q(27, 16) = Q(8, 0).init(r.RGBC.r).mul(r.IR1.as_q3f12).lift(4).widen(Q(27, 16));
    const step_a2: Q(27, 16) = Q(8, 0).init(r.RGBC.g).mul(r.IR2.as_q3f12).lift(4).widen(Q(27, 16));
    const step_a3: Q(27, 16) = Q(8, 0).init(r.RGBC.b).mul(r.IR3.as_q3f12).lift(4).widen(Q(27, 16));

    // On real HW the MAC write probably happens here, but it shouldn't have side effects.

    // IR0=Interpolation value.
    //   [MAC1,MAC2,MAC3] = MAC+(FC-MAC)*IR0                   ;<--- for NCDx only
    //   or rather:
    //   [IR1,IR2,IR3] = (([RFC,GFC,BFC] SHL 12) - [MAC1,MAC2,MAC3]) SAR (sf*12)
    //   [MAC1,MAC2,MAC3] = (([IR1,IR2,IR3] * IR0) + [MAC1,MAC2,MAC3])

    const step_b1: Q(27, 16) = r.RFC.lift(12).sub(step_a1);
    const step_b2: Q(27, 16) = r.GFC.lift(12).sub(step_a2);
    const step_b3: Q(27, 16) = r.BFC.lift(12).sub(step_a3);

    r.MAC1.as_q27f4 = .init(mac_sar12(step_b1, instruction.sf));
    r.MAC2.as_q27f4 = .init(mac_sar12(step_b2, instruction.sf));
    r.MAC3.as_q27f4 = .init(mac_sar12(step_b3, instruction.sf));

    r.IR1.as_q11f4 = r.MAC1.as_q27f4.truncate(Q(11, 4));
    r.IR2.as_q11f4 = r.MAC2.as_q27f4.truncate(Q(11, 4));
    r.IR3.as_q11f4 = r.MAC3.as_q27f4.truncate(Q(11, 4));

    const step_c1: Q(27, 16) = r.IR1.as_q11f4.mul(r.IR0).widen(Q(27, 16)).add(step_a1);
    const step_c2: Q(27, 16) = r.IR2.as_q11f4.mul(r.IR0).widen(Q(27, 16)).add(step_a2);
    const step_c3: Q(27, 16) = r.IR3.as_q11f4.mul(r.IR0).widen(Q(27, 16)).add(step_a3);

    r.MAC1.as_q27f4 = .init(mac_sar12(step_c1, instruction.sf));
    r.MAC2.as_q27f4 = .init(mac_sar12(step_c2, instruction.sf));
    r.MAC3.as_q27f4 = .init(mac_sar12(step_c3, instruction.sf));

    r.IR1.as_q11f4 = r.MAC1.as_q27f4.truncate(Q(11, 4));
    r.IR2.as_q11f4 = r.MAC2.as_q27f4.truncate(Q(11, 4));
    r.IR3.as_q11f4 = r.MAC3.as_q27f4.truncate(Q(11, 4));

    // FIXME
    //   Color FIFO = [MAC1/16,MAC2/16,MAC3/16,CODE], [IR1,IR2,IR3] = [MAC1,MAC2,MAC3]
    const color: state.ColorRGBCode = .{
        .r = @intCast(std.math.clamp(r.MAC1.raw, 0, 0xf_ff) >> 4),
        .g = @intCast(std.math.clamp(r.MAC2.raw, 0, 0xf_ff) >> 4),
        .b = @intCast(std.math.clamp(r.MAC3.raw, 0, 0xf_ff) >> 4),
        .code = r.RGBC.code,
    };

    push_color_fifo(&psx.gte.regs, color);
}

fn execute_nccs(psx: *PSXState, instruction: instructions.GTECommand) void {
    _ = psx;
    _ = instruction;
    @panic("Unimplemented");
}

fn execute_ncct(psx: *PSXState, instruction: instructions.GTECommand) void {
    _ = psx;
    _ = instruction;
    @panic("Unimplemented");
}

fn execute_cdp(psx: *PSXState, instruction: instructions.GTECommand) void {
    _ = psx;
    _ = instruction;
    @panic("Unimplemented");
}

fn execute_cc(psx: *PSXState, instruction: instructions.GTECommand) void {
    _ = psx;
    _ = instruction;
    @panic("Unimplemented");
}

fn execute_nclip(psx: *PSXState, _: instructions.GTECommand) void {
    // COP2 1400006h - 8 Cycles - NCLIP - Normal clipping
    //
    //   MAC0 =   SX0*SY1 + SX1*SY2 + SX2*SY0 - SX0*SY2 - SX1*SY0 - SX2*SY1
    //
    // The sign of the result indicates whether the polygon coordinates are arranged clockwise or anticlockwise
    // (ie. whether the front side or backside is visible). If the result is zero, then it's neither one
    // (ie. the vertices are all arranged in a straight line).
    // Note: The GPU probably renders straight lines as invisble 0 pixel width lines?
    const r = &psx.gte.regs.typed;

    var nclip = std.math.mulWide(i16, r.S0.x, r.S1.y);
    nclip += std.math.mulWide(i16, r.S1.x, r.S2.y);
    nclip += std.math.mulWide(i16, r.S2.x, r.S0.y);
    nclip -= std.math.mulWide(i16, r.S0.x, r.S2.y);
    nclip -= std.math.mulWide(i16, r.S1.x, r.S0.y);
    nclip -= std.math.mulWide(i16, r.S2.x, r.S1.y);

    r.MAC0 = nclip;
}

fn execute_avsz3(psx: *PSXState, instruction: instructions.GTECommand) void {
    _ = psx;
    _ = instruction;
    @panic("Unimplemented");
}

fn execute_avsz4(psx: *PSXState, instruction: instructions.GTECommand) void {
    _ = psx;
    _ = instruction;
    @panic("Unimplemented");
}

fn execute_op_sf(psx: *PSXState, instruction: instructions.GTECommand) void {
    _ = psx;
    _ = instruction;
    @panic("Unimplemented");
}

fn execute_gpf_sf(psx: *PSXState, instruction: instructions.GTECommand) void {
    _ = psx;
    _ = instruction;
    @panic("Unimplemented");
}

fn execute_gpl_sf(psx: *PSXState, instruction: instructions.GTECommand) void {
    _ = psx;
    _ = instruction;
    @panic("Unimplemented");
}

fn push_position_xy_fifo(regs: *GTERegisters, pos: GTERegisters.PosType) void {
    regs.typed.S0 = regs.typed.S1;
    regs.typed.S1 = regs.typed.S2;
    regs.typed.S2 = pos;
    regs.typed.SP = pos; // FIXME
}

fn push_position_z_fifo(regs: *GTERegisters, z: u16) void {
    regs.typed.SZ0 = regs.typed.SZ1;
    regs.typed.SZ1 = regs.typed.SZ2;
    regs.typed.SZ2 = regs.typed.SZ3;
    regs.typed.SZ3 = z;
}

fn push_color_fifo(regs: *GTERegisters, color: state.ColorRGBCode) void {
    regs.typed.RGB0 = regs.typed.RGB1;
    regs.typed.RGB1 = regs.typed.RGB2;
    regs.typed.RGB2 = color;
}

inline fn mac_sar12(q: anytype, sf: bool) i32 {
    const QType = @TypeOf(q);
    if (QType.TotalBits > 44) {
        @compileError("mac_sar12 expects a 44-bit fixed-point value");
    }
    return if (sf) @intCast(q.backing_value >> 12) else @truncate(q.backing_value);
}
