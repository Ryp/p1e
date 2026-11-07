const std = @import("std");

const config = @import("../config.zig");
const state = @import("state.zig");
const instructions = @import("instructions.zig");
const GTERegisters = state.GTERegisters;
const PSXState = @import("../state.zig").PSXState;

fn load_data_reg(regs: *const GTERegisters, register: GTERegisters.DataName) u32 {
    std.debug.print("GTE data load {}\n", .{register});

    return switch (register) {
        .cop2r15 => @panic("Unimplemented"),
        .cop2r28, .cop2r29 => @panic("Unimplemented"),
        else => regs.data.raw[@backingInt(register)],
    };
}

// We don't truncate when registers only have 16 bit values.
// Just make sure the unused bits don't get read.
fn store_data_reg(regs: *GTERegisters, register: GTERegisters.DataName, value: u32) void {
    std.debug.print("GTE data store {} with {x}\n", .{ register, value });

    switch (register) {
        .cop2r15 => @panic("Unimplemented"),
        .cop2r28 => @panic("Unimplemented"),
        .cop2r29 => @panic("Unimplemented"),
        .cop2r31 => @panic("Unimplemented"),
        else => regs.data.raw[@backingInt(register)] = value,
    }
}

fn load_ctrl_reg(regs: *const GTERegisters, register: GTERegisters.CtrlName) u32 {
    std.debug.print("GTE ctrl load {}\n", .{register});

    _ = regs;

    return switch (register) {
        else => @panic("Unimplemented"),
        // else => self.regs.ctrl.raw[@backingInt(register)],
    };
}

// We don't truncate when registers only have 16 bit values.
// Just make sure the unused bits don't get read.
fn store_ctrl_reg(regs: *GTERegisters, register: GTERegisters.CtrlName, value: u32) void {
    std.debug.print("GTE ctrl store {} with {x}\n", .{ register, value });

    switch (register) {
        .FLAG => regs.ctrl.raw[@backingInt(register)] = value & 0x7f_ff_f0_00,
        else => regs.ctrl.raw[@backingInt(register)] = value,
    }
}

pub fn execute_ctc(psx: *PSXState, register_index: u5, value: u32) void {
    if (config.enable_gte_debug) {
        std.debug.print("ctc2 mv {x} to ctrl register {}\n", .{ value, register_index });
    }

    store_ctrl_reg(&psx.gte.regs, @fromBackingInt(register_index), value);
}

pub fn execute_lwc(psx: *PSXState, register_index: u5, value: u32) void {
    if (config.enable_gte_debug) {
        std.debug.print("lwc2 mv {x} to data register {}\n", .{ value, register_index });
    }

    store_data_reg(&psx.gte.regs, @fromBackingInt(register_index), value);
}

pub fn execute_cop(psx: *PSXState, instruction: instructions.GTECommand) void {
    std.debug.print("GTE instruction {}\n", .{instruction});

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
    _ = psx;
    _ = instruction;
    @panic("Unimplemented");
}

fn execute_rtpt(psx: *PSXState, instruction: instructions.GTECommand) void {
    _ = psx;
    _ = instruction;
    @panic("Unimplemented");
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

fn execute_ncds(psx: *PSXState, instruction: instructions.GTECommand) void {
    _ = psx;
    _ = instruction;
    @panic("Unimplemented");
}

fn execute_ncdt(psx: *PSXState, instruction: instructions.GTECommand) void {
    _ = psx;
    _ = instruction;
    @panic("Unimplemented");
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

fn execute_nclip(psx: *PSXState, instruction: instructions.GTECommand) void {
    _ = psx;
    _ = instruction;
    @panic("Unimplemented");
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
