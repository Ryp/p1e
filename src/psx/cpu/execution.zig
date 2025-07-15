const std = @import("std");

const PSXState = @import("../state.zig").PSXState;
const config = @import("../config.zig");

const cpu = @import("state.zig");
const Registers = cpu.Registers;

const mmio = @import("../mmio.zig");

const instructions = @import("instructions.zig");
const debug = @import("debug.zig");

pub fn step(psx: *PSXState) void {
    psx.cpu.regs.current_instruction_pc = psx.cpu.regs.pc;

    if (psx.cpu.regs.pc % 4 != 0) {
        execute_exception(psx, .AdEL);
        return;
    }

    const op_code = mmio.load_u32(psx, psx.cpu.regs.pc);

    psx.cpu.regs.pc = psx.cpu.regs.next_pc;
    psx.cpu.regs.next_pc +%= 4;

    // Execute any pending memory loads
    if (psx.cpu.regs.pending_load) |pending_load| {
        store_reg(&psx.cpu.regs, pending_load.register, pending_load.value);
        psx.cpu.regs.pending_load = null;
    }

    const instruction = instructions.decode_instruction(op_code);

    if (config.enable_debug_print) {
        debug.print_instruction(instruction);
    }

    psx.cpu.delay_slot = psx.cpu.branch;
    psx.cpu.branch = false;

    if ((psx.cpu.regs.sr.interrupt_stack.current.enabled) and (@as(u3, @bitCast(psx.cpu.regs.cause.interrupt_pending)) & psx.cpu.regs.sr.interrupt_mask) != 0) {
        execute_exception(psx, .INT);
    } else {
        execute_instruction(psx, instruction);
    }

    // Do this when exactly?
    @memcpy(&psx.cpu.regs.r_in, &psx.cpu.regs.r_out);
}

fn execute_instruction(psx: *PSXState, instruction: instructions.Instruction) void {
    switch (instruction) {
        .sll => |i| execute_sll(psx, i),
        .srl => |i| execute_srl(psx, i),
        .sra => |i| execute_sra(psx, i),
        .sllv => |i| execute_sllv(psx, i),
        .srlv => |i| execute_srlv(psx, i),
        .srav => |i| execute_srav(psx, i),
        .jr => |i| execute_jr(psx, i),
        .jalr => |i| execute_jalr(psx, i),
        .syscall => execute_syscall(psx),
        .break_ => execute_break(psx),
        .mfhi => |i| execute_mfhi(psx, i),
        .mthi => |i| execute_mthi(psx, i),
        .mflo => |i| execute_mflo(psx, i),
        .mtlo => |i| execute_mtlo(psx, i),
        .rfe => execute_rfe(psx),
        .cop1 => execute_cop1(psx),
        .cop2 => execute_cop2(psx),
        .cop3 => execute_cop3(psx),
        .mult => |i| execute_mult(psx, i),
        .multu => |i| execute_multu(psx, i),
        .div => |i| execute_div(psx, i),
        .divu => |i| execute_divu(psx, i),
        .add => |i| execute_add(psx, i),
        .addu => |i| execute_addu(psx, i),
        .sub => |i| execute_sub(psx, i),
        .subu => |i| execute_subu(psx, i),
        .and_ => |i| execute_and(psx, i),
        .or_ => |i| execute_or(psx, i),
        .xor => |i| execute_xor(psx, i),
        .nor => |i| execute_nor(psx, i),
        .slt => |i| execute_slt(psx, i),
        .sltu => |i| execute_sltu(psx, i),
        .b_cond_z => |i| execute_b_cond_z(psx, i),
        .j => |i| execute_j(psx, i),
        .jal => |i| execute_jal(psx, i),
        .beq => |i| execute_beq(psx, i),
        .bne => |i| execute_bne(psx, i),
        .blez => |i| execute_blez(psx, i),
        .bgtz => |i| execute_bgtz(psx, i),
        .mfc => |i| execute_mfc(psx, i),
        .cfc => |i| execute_cfc(psx, i),
        .mtc => |i| execute_mtc(psx, i),
        .ctc => |i| execute_ctc(psx, i),
        .bcn => |i| execute_bcn(psx, i),
        .addi => |i| execute_addi(psx, i),
        .addiu => |i| execute_addiu(psx, i),
        .slti => |i| execute_slti(psx, i),
        .sltiu => |i| execute_sltiu(psx, i),
        .andi => |i| execute_andi(psx, i),
        .ori => |i| execute_ori(psx, i),
        .xori => |i| execute_xori(psx, i),
        .lui => |i| execute_lui(psx, i),

        .lb => |i| execute_lb(psx, i),
        .lh => |i| execute_lh(psx, i),
        .lwl => |i| execute_lwl(psx, i),
        .lw => |i| execute_lw(psx, i),
        .lbu => |i| execute_lbu(psx, i),
        .lhu => |i| execute_lhu(psx, i),
        .lwr => |i| execute_lwr(psx, i),
        .sb => |i| execute_sb(psx, i),
        .sh => |i| execute_sh(psx, i),
        .swl => |i| execute_swl(psx, i),
        .sw => |i| execute_sw(psx, i),
        .swr => |i| execute_swr(psx, i),

        .lwc => |i| execute_lwc(psx, i),
        .swc => |i| execute_swc(psx, i),

        .invalid => execute_reserved_instruction(psx),
    }
}

fn load_reg(registers: Registers, register_name: cpu.RegisterName) u32 {
    const value = switch (register_name) {
        .zero => 0,
        else => registers.r_in[@intFromEnum(register_name)],
    };

    if (config.enable_debug_print) {
        std.debug.print("reg load 0x{x:0>8} from {}\n", .{ value, register_name });
    }

    return value;
}

fn store_reg(registers: *Registers, register_name: cpu.RegisterName, value: u32) void {
    if (config.enable_debug_print) {
        std.debug.print("reg store 0x{x:0>8} in {}\n", .{ value, register_name });
    }

    switch (register_name) {
        .zero => {},
        else => registers.r_out[@intFromEnum(register_name)] = value,
    }
}

fn execute_sll(psx: *PSXState, instruction: instructions.sll) void {
    const value = load_reg(psx.cpu.regs, instruction.rt);

    const result = value << instruction.shift_imm;

    store_reg(&psx.cpu.regs, instruction.rd, result);
}

fn execute_srl(psx: *PSXState, instruction: instructions.srl) void {
    const value = load_reg(psx.cpu.regs, instruction.rt);

    const result = value >> instruction.shift_imm;

    store_reg(&psx.cpu.regs, instruction.rd, result);
}

fn execute_sra(psx: *PSXState, instruction: instructions.sra) void {
    const value: i32 = @bitCast(load_reg(psx.cpu.regs, instruction.rt));

    // Sign-extending
    const result = value >> instruction.shift_imm;

    store_reg(&psx.cpu.regs, instruction.rd, @bitCast(result));
}

fn execute_sllv(psx: *PSXState, instruction: instructions.sllv) void {
    const value = load_reg(psx.cpu.regs, instruction.rt);
    const shift: u5 = @truncate(load_reg(psx.cpu.regs, instruction.rs));

    const result = value << shift;

    store_reg(&psx.cpu.regs, instruction.rd, result);
}

fn execute_srlv(psx: *PSXState, instruction: instructions.srlv) void {
    const value = load_reg(psx.cpu.regs, instruction.rt);
    const shift: u5 = @truncate(load_reg(psx.cpu.regs, instruction.rs));

    const result = value >> shift;

    store_reg(&psx.cpu.regs, instruction.rd, result);
}

fn execute_srav(psx: *PSXState, instruction: instructions.srav) void {
    const value: i32 = @bitCast(load_reg(psx.cpu.regs, instruction.rt));
    const shift: u5 = @truncate(load_reg(psx.cpu.regs, instruction.rs));

    // Sign-extending
    const result = value >> shift;

    store_reg(&psx.cpu.regs, instruction.rd, @bitCast(result));
}

fn execute_jr(psx: *PSXState, instruction: instructions.jr) void {
    const address = load_reg(psx.cpu.regs, instruction.rs);
    execute_generic_jump(psx, address);
}

fn execute_jalr(psx: *PSXState, instruction: instructions.jalr) void {
    store_reg(&psx.cpu.regs, instruction.rd, psx.cpu.regs.next_pc);

    const address = load_reg(psx.cpu.regs, instruction.rs);
    execute_generic_jump(psx, address);
}

fn execute_syscall(psx: *PSXState) void {
    execute_exception(psx, .SysCall);
}

fn execute_break(psx: *PSXState) void {
    execute_exception(psx, .BP);
}

fn execute_mult(psx: *PSXState, instruction: instructions.mult) void {
    const a: i64 = @as(i32, @bitCast(load_reg(psx.cpu.regs, instruction.rs)));
    const b: i64 = @as(i32, @bitCast(load_reg(psx.cpu.regs, instruction.rt)));

    const result: u64 = @bitCast(a * b);

    psx.cpu.regs.hi = @truncate(result >> 32);
    psx.cpu.regs.lo = @truncate(result);
}

fn execute_multu(psx: *PSXState, instruction: instructions.multu) void {
    const a: u64 = load_reg(psx.cpu.regs, instruction.rs);
    const b: u64 = load_reg(psx.cpu.regs, instruction.rt);

    const result = a * b;

    psx.cpu.regs.hi = @truncate(result >> 32);
    psx.cpu.regs.lo = @truncate(result);
}

fn execute_div(psx: *PSXState, instruction: instructions.div) void {
    const numerator_u32 = load_reg(psx.cpu.regs, instruction.rs);
    const numerator: i32 = @bitCast(numerator_u32);
    const divisor: i32 = @bitCast(load_reg(psx.cpu.regs, instruction.rt));

    if (divisor == 0) {
        // Division by zero
        psx.cpu.regs.hi = @bitCast(numerator);
        psx.cpu.regs.lo = if (numerator < 0) 1 else 0xff_ff_ff_ff;
    } else if (numerator_u32 == 0x80_00_00_00 and divisor == -1) {
        // Result can't be represented
        psx.cpu.regs.hi = 0;
        psx.cpu.regs.lo = numerator_u32;
    } else {
        psx.cpu.regs.hi = @bitCast(@rem(numerator, divisor));
        psx.cpu.regs.lo = @bitCast(@divTrunc(numerator, divisor));
    }
}

fn execute_divu(psx: *PSXState, instruction: instructions.divu) void {
    const numerator = load_reg(psx.cpu.regs, instruction.rs);
    const divisor = load_reg(psx.cpu.regs, instruction.rt);

    if (divisor == 0) {
        // Division by zero
        psx.cpu.regs.hi = numerator;
        psx.cpu.regs.lo = 0xff_ff_ff_ff;
    } else {
        psx.cpu.regs.hi = @rem(numerator, divisor);
        psx.cpu.regs.lo = @divTrunc(numerator, divisor);
    }
}

fn execute_add(psx: *PSXState, instruction: instructions.add) void {
    const value_s = load_reg(psx.cpu.regs, instruction.rs);
    const value_t = load_reg(psx.cpu.regs, instruction.rt);

    const result, const overflow = execute_generic_add_with_overflow(value_s, @bitCast(value_t));

    if (overflow) {
        execute_exception(psx, .Ov);
    } else {
        store_reg(&psx.cpu.regs, instruction.rd, result);
    }
}

fn execute_addu(psx: *PSXState, instruction: instructions.addu) void {
    const value_s = load_reg(psx.cpu.regs, instruction.rs);
    const value_t = load_reg(psx.cpu.regs, instruction.rt);

    const result = value_s +% value_t;

    store_reg(&psx.cpu.regs, instruction.rd, result);
}

fn execute_sub(psx: *PSXState, instruction: instructions.sub) void {
    const value_s = load_reg(psx.cpu.regs, instruction.rs);
    const value_t = load_reg(psx.cpu.regs, instruction.rt);

    const result, const overflow = execute_generic_sub_with_overflow(value_s, @bitCast(value_t));

    if (overflow) {
        execute_exception(psx, .Ov);
    } else {
        store_reg(&psx.cpu.regs, instruction.rd, result);
    }
}

fn execute_subu(psx: *PSXState, instruction: instructions.subu) void {
    const value_s = load_reg(psx.cpu.regs, instruction.rs);
    const value_t = load_reg(psx.cpu.regs, instruction.rt);

    const result = value_s -% value_t;

    store_reg(&psx.cpu.regs, instruction.rd, result);
}

fn execute_and(psx: *PSXState, instruction: instructions.and_) void {
    const value_s = load_reg(psx.cpu.regs, instruction.rs);
    const value_t = load_reg(psx.cpu.regs, instruction.rt);

    store_reg(&psx.cpu.regs, instruction.rd, value_s & value_t);
}

fn execute_or(psx: *PSXState, instruction: instructions.or_) void {
    const value_s = load_reg(psx.cpu.regs, instruction.rs);
    const value_t = load_reg(psx.cpu.regs, instruction.rt);

    store_reg(&psx.cpu.regs, instruction.rd, value_s | value_t);
}

fn execute_xor(psx: *PSXState, instruction: instructions.xor) void {
    const value_s = load_reg(psx.cpu.regs, instruction.rs);
    const value_t = load_reg(psx.cpu.regs, instruction.rt);

    store_reg(&psx.cpu.regs, instruction.rd, value_s ^ value_t);
}

fn execute_nor(psx: *PSXState, instruction: instructions.nor) void {
    const value_s = load_reg(psx.cpu.regs, instruction.rs);
    const value_t = load_reg(psx.cpu.regs, instruction.rt);

    store_reg(&psx.cpu.regs, instruction.rd, ~(value_s | value_t));
}

fn execute_slt(psx: *PSXState, instruction: instructions.slt) void {
    const value_s: i32 = @bitCast(load_reg(psx.cpu.regs, instruction.rs));
    const value_t: i32 = @bitCast(load_reg(psx.cpu.regs, instruction.rt));

    const result: u32 = if (value_s < value_t) 1 else 0;

    store_reg(&psx.cpu.regs, instruction.rd, result);
}

fn execute_sltu(psx: *PSXState, instruction: instructions.sltu) void {
    const value_s = load_reg(psx.cpu.regs, instruction.rs);
    const value_t = load_reg(psx.cpu.regs, instruction.rt);

    const result: u32 = if (value_s < value_t) 1 else 0;

    store_reg(&psx.cpu.regs, instruction.rd, result);
}

fn execute_b_cond_z(psx: *PSXState, instruction: instructions.b_cond_z) void {
    const value_s: i32 = @bitCast(load_reg(psx.cpu.regs, instruction.rs));

    var test_value = value_s < 0;

    // Flip test if needed
    test_value = test_value != instruction.test_greater;

    if (test_value) {
        if (instruction.link) {
            store_reg(&psx.cpu.regs, cpu.RegisterName.ra, psx.cpu.regs.next_pc);
        }

        execute_generic_branch(psx, instruction.rel_offset);
    }
}

fn execute_j(psx: *PSXState, instruction: instructions.j) void {
    const address = (psx.cpu.regs.next_pc & 0xf0_00_00_00) | instruction.offset;
    execute_generic_jump(psx, address);
}

fn execute_jal(psx: *PSXState, instruction: instructions.jal) void {
    store_reg(&psx.cpu.regs, cpu.RegisterName.ra, psx.cpu.regs.next_pc);

    const address = (psx.cpu.regs.next_pc & 0xf0_00_00_00) | instruction.offset;
    execute_generic_jump(psx, address);
}

fn execute_beq(psx: *PSXState, instruction: instructions.beq) void {
    const value_s = load_reg(psx.cpu.regs, instruction.rs);
    const value_t = load_reg(psx.cpu.regs, instruction.rt);

    if (value_s == value_t) {
        execute_generic_branch(psx, instruction.rel_offset);
    }
}

fn execute_bne(psx: *PSXState, instruction: instructions.bne) void {
    const value_s = load_reg(psx.cpu.regs, instruction.rs);
    const value_t = load_reg(psx.cpu.regs, instruction.rt);

    if (value_s != value_t) {
        execute_generic_branch(psx, instruction.rel_offset);
    }
}

fn execute_blez(psx: *PSXState, instruction: instructions.blez) void {
    const value_s: i32 = @bitCast(load_reg(psx.cpu.regs, instruction.rs));

    if (value_s <= 0) {
        execute_generic_branch(psx, instruction.rel_offset);
    }
}

fn execute_bgtz(psx: *PSXState, instruction: instructions.bgtz) void {
    const value_s: i32 = @bitCast(load_reg(psx.cpu.regs, instruction.rs));

    if (value_s > 0) {
        execute_generic_branch(psx, instruction.rel_offset);
    }
}

fn execute_mfc(psx: *PSXState, instruction: instructions.mtc) void {
    std.debug.assert(instruction.cop_index == 0);

    const value: u32 = switch (instruction.target) {
        .BPC, .BDA, .JUMPDEST, .DCIC, .BadVaddr, .BDAM, .BPCM, .PRID => unreachable,
        .SR => @bitCast(psx.cpu.regs.sr),
        .CAUSE => @bitCast(psx.cpu.regs.cause),
        .EPC => psx.cpu.regs.epc,
        _ => unreachable,
    };

    psx.cpu.regs.pending_load = .{ .register = instruction.cpu_rs, .value = @bitCast(value) };
}

fn execute_cfc(psx: *PSXState, instruction: instructions.cfc) void {
    _ = psx;
    _ = instruction;
    unreachable;
}

fn execute_mtc(psx: *PSXState, instruction: instructions.mtc) void {
    std.debug.assert(instruction.cop_index == 0);

    const value = load_reg(psx.cpu.regs, instruction.cpu_rs);

    switch (instruction.target) {
        .BPC, .BDA, .JUMPDEST, .DCIC, .BadVaddr, .BDAM, .BPCM, .PRID => {
            if (config.enable_debug_print) {
                std.debug.print("FIXME mtc0 target write ignored\n", .{});
            }
        },
        .SR => psx.cpu.regs.sr = @bitCast(value),
        .CAUSE => switch (value) {
            0 => {
                const cause_new: @TypeOf(psx.cpu.regs.cause) = @bitCast(value);

                // Only those two bits are R/W
                psx.cpu.regs.cause.interrupt_pending.software_irq0 = cause_new.interrupt_pending.software_irq0;
                psx.cpu.regs.cause.interrupt_pending.software_irq1 = cause_new.interrupt_pending.software_irq1;
            },
            else => unreachable,
        },
        .EPC => unreachable,
        _ => unreachable,
    }
}

fn execute_ctc(psx: *PSXState, instruction: instructions.ctc) void {
    _ = psx;
    _ = instruction;
    unreachable;
}

fn execute_bcn(psx: *PSXState, instruction: instructions.bcn) void {
    _ = psx;
    _ = instruction;
    unreachable;
}

fn execute_addi(psx: *PSXState, instruction: instructions.addi) void {
    const value_s = load_reg(psx.cpu.regs, instruction.rs);

    const result, const overflow = execute_generic_add_with_overflow(value_s, instruction.imm_i16);

    if (overflow) {
        execute_exception(psx, .Ov);
    } else {
        store_reg(&psx.cpu.regs, instruction.rt, result);
    }
}

fn execute_addiu(psx: *PSXState, instruction: instructions.addiu) void {
    const value_s = load_reg(psx.cpu.regs, instruction.rs);

    const result = wrapping_add_u32_i32(value_s, instruction.imm_i16);

    store_reg(&psx.cpu.regs, instruction.rt, result);
}

fn execute_slti(psx: *PSXState, instruction: instructions.slti) void {
    const value_s: i32 = @bitCast(load_reg(psx.cpu.regs, instruction.rs));

    const result: u32 = if (value_s < instruction.imm_i16) 1 else 0;

    store_reg(&psx.cpu.regs, instruction.rt, result);
}

fn execute_sltiu(psx: *PSXState, instruction: instructions.sltiu) void {
    const value_s = load_reg(psx.cpu.regs, instruction.rs);

    const result: u32 = if (value_s < instruction.imm_i16) 1 else 0;

    store_reg(&psx.cpu.regs, instruction.rt, result);
}

fn execute_andi(psx: *PSXState, instruction: instructions.andi) void {
    const value = load_reg(psx.cpu.regs, instruction.rs);

    store_reg(&psx.cpu.regs, instruction.rt, value & instruction.imm_u16);
}

fn execute_ori(psx: *PSXState, instruction: instructions.ori) void {
    const value = load_reg(psx.cpu.regs, instruction.rs);

    store_reg(&psx.cpu.regs, instruction.rt, value | instruction.imm_u16);
}

fn execute_xori(psx: *PSXState, instruction: instructions.xori) void {
    const value = load_reg(psx.cpu.regs, instruction.rs);

    store_reg(&psx.cpu.regs, instruction.rt, value ^ instruction.imm_u16);
}

fn execute_lui(psx: *PSXState, instruction: instructions.lui) void {
    const value = @as(u32, instruction.imm_u16) << 16;

    store_reg(&psx.cpu.regs, instruction.rt, value);
}

fn execute_lb(psx: *PSXState, instruction: instructions.lb) void {
    const address_base = load_reg(psx.cpu.regs, instruction.rs);
    const address = wrapping_add_u32_i32(address_base, instruction.imm_i16);

    const value: i8 = @bitCast(mmio.load_u8(psx, address));
    const value_sign_extended: i32 = value;

    psx.cpu.regs.pending_load = .{ .register = instruction.rt, .value = @bitCast(value_sign_extended) };
}

fn execute_lbu(psx: *PSXState, instruction: instructions.lbu) void {
    const address_base = load_reg(psx.cpu.regs, instruction.rs);
    const address = wrapping_add_u32_i32(address_base, instruction.imm_i16);

    const value: u8 = mmio.load_u8(psx, address);

    psx.cpu.regs.pending_load = .{ .register = instruction.rt, .value = value };
}

fn execute_lh(psx: *PSXState, instruction: instructions.lh) void {
    const address_base = load_reg(psx.cpu.regs, instruction.rs);
    const address = wrapping_add_u32_i32(address_base, instruction.imm_i16);

    if (address % 2 == 0) {
        const value: i16 = @bitCast(mmio.load_u16(psx, address));
        const value_sign_extended: i32 = value;

        psx.cpu.regs.pending_load = .{ .register = instruction.rt, .value = @bitCast(value_sign_extended) };
    } else {
        execute_exception(psx, .AdEL);
    }
}

fn execute_lhu(psx: *PSXState, instruction: instructions.lhu) void {
    const address_base = load_reg(psx.cpu.regs, instruction.rs);
    const address = wrapping_add_u32_i32(address_base, instruction.imm_i16);

    if (address % 2 == 0) {
        const value = mmio.load_u16(psx, address);

        psx.cpu.regs.pending_load = .{ .register = instruction.rt, .value = value };
    } else {
        execute_exception(psx, .AdEL);
    }
}

fn execute_lw(psx: *PSXState, instruction: instructions.lw) void {
    const address_base = load_reg(psx.cpu.regs, instruction.rs);
    const address = wrapping_add_u32_i32(address_base, instruction.imm_i16);

    if (address % 4 == 0) {
        const value = mmio.load_u32(psx, address);

        psx.cpu.regs.pending_load = .{ .register = instruction.rt, .value = value };
    } else {
        execute_exception(psx, .AdEL);
    }
}

fn execute_lwl(psx: *PSXState, instruction: instructions.lwl) void {
    const address_base = load_reg(psx.cpu.regs, instruction.rs);
    const address = wrapping_add_u32_i32(address_base, instruction.imm_i16);
    const address_aligned = address & ~@as(u32, 0b11);

    const load_value = mmio.load_u32(psx, address_aligned);

    const previous_value = if (psx.cpu.regs.pending_load) |pending_load|
        if (pending_load.is_unaligned) pending_load.value else 0
    else
        0;

    const result = switch (address % 4) {
        0 => previous_value & 0x00_ff_ff_ff | load_value << 24,
        1 => previous_value & 0x00_00_ff_ff | load_value << 16,
        2 => previous_value & 0x00_00_00_ff | load_value << 8,
        3 => previous_value & 0x00_00_00_00 | load_value << 0,
        else => unreachable,
    };

    psx.cpu.regs.pending_load = .{ .register = instruction.rt, .value = result };
}

fn execute_lwr(psx: *PSXState, instruction: instructions.lwr) void {
    const address_base = load_reg(psx.cpu.regs, instruction.rs);
    const address = wrapping_add_u32_i32(address_base, instruction.imm_i16);
    const address_aligned = address & ~@as(u32, 0b11);

    const load_value = mmio.load_u32(psx, address_aligned);

    const previous_value = if (psx.cpu.regs.pending_load) |pending_load|
        if (pending_load.is_unaligned) pending_load.value else 0
    else
        0;

    const result = switch (address % 4) {
        0 => previous_value & 0x00_00_00_00 | load_value >> 0,
        1 => previous_value & 0xff_00_00_00 | load_value >> 8,
        2 => previous_value & 0xff_ff_00_00 | load_value >> 16,
        3 => previous_value & 0xff_ff_ff_00 | load_value >> 24,
        else => unreachable,
    };

    psx.cpu.regs.pending_load = .{ .register = instruction.rt, .value = result };
}

fn execute_sb(psx: *PSXState, instruction: instructions.sb) void {
    const value = load_reg(psx.cpu.regs, instruction.rt);

    const address_base = load_reg(psx.cpu.regs, instruction.rs);
    const address = wrapping_add_u32_i32(address_base, instruction.imm_i16);

    mmio.store_u8(psx, address, @truncate(value));
}

fn execute_sh(psx: *PSXState, instruction: instructions.sh) void {
    const value = load_reg(psx.cpu.regs, instruction.rt);

    const address_base = load_reg(psx.cpu.regs, instruction.rs);
    const address = wrapping_add_u32_i32(address_base, instruction.imm_i16);

    if (address % 2 == 0) {
        mmio.store_u16(psx, address, @truncate(value));
    } else {
        execute_exception(psx, .AdES);
    }
}

fn execute_sw(psx: *PSXState, instruction: instructions.sw) void {
    const value = load_reg(psx.cpu.regs, instruction.rt);

    const address_base = load_reg(psx.cpu.regs, instruction.rs);
    const address = wrapping_add_u32_i32(address_base, instruction.imm_i16);

    if (address % 4 == 0) {
        mmio.store_u32(psx, address, value);
    } else {
        execute_exception(psx, .AdES);
    }
}

fn execute_swl(psx: *PSXState, instruction: instructions.swl) void {
    const value = load_reg(psx.cpu.regs, instruction.rt);

    const address_base = load_reg(psx.cpu.regs, instruction.rs);
    const address = wrapping_add_u32_i32(address_base, instruction.imm_i16);
    const address_aligned = address & ~@as(u32, 0b11);

    const previous_value = mmio.load_u32(psx, address_aligned);

    const result = switch (address % 4) {
        0 => previous_value & 0xff_ff_ff_00 | value >> 24,
        1 => previous_value & 0xff_ff_00_00 | value >> 16,
        2 => previous_value & 0xff_00_00_00 | value >> 8,
        3 => previous_value & 0x00_00_00_00 | value >> 0,
        else => unreachable,
    };

    mmio.store_u32(psx, address_aligned, result);
}

fn execute_swr(psx: *PSXState, instruction: instructions.swr) void {
    const value = load_reg(psx.cpu.regs, instruction.rt);

    const address_base = load_reg(psx.cpu.regs, instruction.rs);
    const address = wrapping_add_u32_i32(address_base, instruction.imm_i16);
    const address_aligned = address & ~@as(u32, 0b11);

    const previous_value = mmio.load_u32(psx, address_aligned);

    const result = switch (address % 4) {
        0 => previous_value & 0x00_00_00_00 | value << 0,
        1 => previous_value & 0x00_00_00_ff | value << 8,
        2 => previous_value & 0x00_00_ff_ff | value << 16,
        3 => previous_value & 0x00_ff_ff_ff | value << 24,
        else => unreachable,
    };

    mmio.store_u32(psx, address_aligned, result);
}

fn execute_mfhi(psx: *PSXState, instruction: instructions.mfhi) void {
    store_reg(&psx.cpu.regs, instruction.rd, psx.cpu.regs.hi);
}

fn execute_mthi(psx: *PSXState, instruction: instructions.mthi) void {
    psx.cpu.regs.hi = load_reg(psx.cpu.regs, instruction.rs);
}

fn execute_mflo(psx: *PSXState, instruction: instructions.mflo) void {
    store_reg(&psx.cpu.regs, instruction.rd, psx.cpu.regs.lo);
}

fn execute_mtlo(psx: *PSXState, instruction: instructions.mtlo) void {
    psx.cpu.regs.lo = load_reg(psx.cpu.regs, instruction.rs);
}

fn execute_rfe(psx: *PSXState) void {
    execute_interrupt_stack_pop(psx);
}

fn execute_cop1(psx: *PSXState) void {
    execute_exception(psx, .CpU);
}

fn execute_cop2(psx: *PSXState) void {
    _ = psx;
    unreachable;
}

fn execute_cop3(psx: *PSXState) void {
    execute_exception(psx, .CpU);
}

fn execute_lwc(psx: *PSXState, instruction: instructions.lwc) void {
    if (instruction.cop_index == 2) {
        unreachable;
    } else {
        execute_exception(psx, .CpU);
    }
}

fn execute_swc(psx: *PSXState, instruction: instructions.swc) void {
    if (instruction.cop_index == 2) {
        unreachable;
    } else {
        execute_exception(psx, .CpU);
    }
}

fn execute_generic_add_with_overflow(lhs: u32, rhs: i32) struct { u32, bool } {
    var result: u32 = undefined;
    var overflow: u1 = undefined;

    if (rhs >= 0) {
        // NOTE: using two's-complement to ignore signedness
        result, overflow = @addWithOverflow(lhs, @as(u32, @intCast(rhs)));
    } else {
        result, overflow = @subWithOverflow(lhs, @as(u32, @intCast(-rhs)));
    }

    return .{ result, overflow != 0 };
}

fn execute_generic_sub_with_overflow(lhs: u32, rhs: i32) struct { u32, bool } {
    var result: u32 = undefined;
    var overflow: u1 = undefined;

    if (rhs >= 0) {
        // NOTE: using two's-complement to ignore signedness
        result, overflow = @subWithOverflow(lhs, @as(u32, @intCast(rhs)));
    } else {
        result, overflow = @addWithOverflow(lhs, @as(u32, @intCast(-rhs)));
    }

    return .{ result, overflow != 0 };
}

fn execute_reserved_instruction(psx: *PSXState) void {
    execute_exception(psx, .RI);
}

fn execute_generic_jump(psx: *PSXState, address: u32) void {
    psx.cpu.branch = true;
    psx.cpu.regs.next_pc = address;
}

fn execute_generic_branch(psx: *PSXState, offset: i32) void {
    psx.cpu.branch = true;
    psx.cpu.regs.next_pc = wrapping_add_u32_i32(psx.cpu.regs.pc, offset);
}

pub fn update_hardware_interrupt_line(psx: *PSXState) void {
    psx.cpu.regs.cause.interrupt_pending.hardware_irq = (psx.mmio.irq.status.raw & psx.mmio.irq.mask.raw != 0);
}

const HardwareInterruptType = enum {
    IRQ0_VBlank, // 0     IRQ0 VBLANK (PAL=50Hz, NTSC=60Hz)
    IRQ1_GPU, //    1     IRQ1 GPU   Can be requested via GP0(1Fh) command (rarely used)
    IRQ2_CDRom, //  2     IRQ2 CDROM
    IRQ3_DMA, //    3     IRQ3 DMA
    IRQ4_TMR0, //   4     IRQ4 TMR0  Timer 0 aka Root Counter 0 (Sysclk or Dotclk)
    IRQ5_TMR1, //   5     IRQ5 TMR1  Timer 1 aka Root Counter 1 (Sysclk or H-blank)
    IRQ6_TMR2, //   6     IRQ6 TMR2  Timer 2 aka Root Counter 2 (Sysclk or Sysclk/8)
    IRQ7_Controller_Memory_Card, //   7     IRQ7 Controller and Memory Card - Byte Received Interrupt
    IRQ8_SIO, //    8     IRQ8 SIO
    IRQ9_SPU, //    9     IRQ9 SPU
    IRQ10_Controller_Lightpen, //   10    IRQ10 Controller - Lightpen Interrupt (reportedly also PIO...?)
};

pub fn request_hardware_interrupt(psx: *PSXState, interrupt: HardwareInterruptType) void {
    const interrupt_bit = @as(u11, 1) << @intFromEnum(interrupt);

    psx.mmio.irq.status.raw |= interrupt_bit;

    update_hardware_interrupt_line(psx);
}

fn execute_exception(psx: *PSXState, cause: cpu.ExceptionCause) void {
    psx.cpu.regs.cause = @bitCast(@as(u32, 0));
    psx.cpu.regs.cause.cause = cause;
    psx.cpu.regs.cause.branch_delay = if (psx.cpu.delay_slot) 1 else 0;

    psx.cpu.regs.epc = psx.cpu.regs.current_instruction_pc;

    if (psx.cpu.delay_slot) {
        psx.cpu.regs.epc -%= 4;
    }

    execute_interrupt_stack_push(psx);

    psx.cpu.regs.pc = if (psx.cpu.regs.sr.bev == 1) 0xbfc00180 else 0x80000080;
    psx.cpu.regs.next_pc = psx.cpu.regs.pc +% 4;
}

fn execute_interrupt_stack_push(psx: *PSXState) void {
    psx.cpu.regs.sr.interrupt_stack.old = psx.cpu.regs.sr.interrupt_stack.previous;
    psx.cpu.regs.sr.interrupt_stack.previous = psx.cpu.regs.sr.interrupt_stack.current;
    psx.cpu.regs.sr.interrupt_stack.current = .{ .enabled = false, .mode = .Kernel };
}

fn execute_interrupt_stack_pop(psx: *PSXState) void {
    psx.cpu.regs.sr.interrupt_stack.current = psx.cpu.regs.sr.interrupt_stack.previous;
    psx.cpu.regs.sr.interrupt_stack.previous = psx.cpu.regs.sr.interrupt_stack.old;
    // NOTE: We don't touch the `old` field here
}

fn wrapping_add_u32_i32(lhs: u32, rhs: i32) u32 {
    // NOTE: using two's-complement to ignore signedness
    return lhs +% @as(u32, @bitCast(rhs));
}
