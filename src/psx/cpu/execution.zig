const std = @import("std");

const PSXState = @import("../state.zig").PSXState;
const config = @import("../config.zig");

const cpu = @import("state.zig");
const Registers = cpu.Registers;

const bus = @import("../bus.zig");
const cdrom = @import("../cdrom/execution.zig");
const gte = @import("../gte/execution.zig");
const exe_sideloading = @import("../exe_sideloading.zig");
const save_state = @import("../save_state.zig");

const instructions = @import("instructions.zig");
const debug = @import("debug.zig");

pub fn step_1k_times(psx: *PSXState) void {
    for (0..1000) |_| {
        step(psx);
    }

    cdrom.execute_ticks(psx, 1000);
}

fn step(psx: *PSXState) void {
    defer psx.step_index += 1;

    if (psx.skip_shell_execution) {
        if (psx.cpu.regs.pc == exe_sideloading.DefaultSideLoadingPC) {
            psx.cpu.regs.pc = load_reg(psx.cpu.regs, .ra);
            psx.cpu.regs.next_pc = psx.cpu.regs.pc + 4;
            psx.cpu.branch = true;

            std.debug.print("Skipping shell execution, jump to 0x{x}\n", .{psx.cpu.regs.pc});
        }
    } else if (psx.load_exe_path) |sideloaded_exe_path| {
        if (psx.cpu.regs.pc == exe_sideloading.DefaultSideLoadingPC) {
            var exe_file = if (std.fs.cwd().openFile(sideloaded_exe_path, .{})) |f| f else |err| {
                std.debug.print("Failed to open exe file: {}\n", .{err});
                return;
            };
            defer exe_file.close();

            exe_sideloading.load(psx, exe_file.deprecatedReader()) catch |err| {
                std.debug.print("Failed to load exe: {}\n", .{err});
            };
        }
    }

    if (psx.save_state_path) |save_state_path| {
        std.debug.assert(psx.save_state_after_ticks != null);

        if (psx.step_index == psx.save_state_after_ticks.?) {
            var save_state_file = if (std.fs.cwd().createFile(save_state_path, .{
                .read = true,
                .truncate = true,
                .exclusive = false, // Set to true will ensure this file is created by us
            })) |f| f else |err| {
                std.debug.print("Failed to create save state file: {}\n", .{err});
                return;
            };
            defer save_state_file.close();

            save_state.save(psx.*, save_state_file.deprecatedWriter()) catch |err| {
                std.debug.print("Failed to save state: {}\n", .{err});
                // FIXME error handling
            };

            @panic("SAVED!");
        }
    }

    const address_typed: bus.Address = @bitCast(psx.cpu.regs.pc);
    const t1_value = load_reg(psx.cpu.regs, .t1);

    if (config.enable_tty_print) {
        if ((address_typed.offset == 0xA0 and t1_value == 0x3C) or (address_typed.offset == 0xB0 and t1_value == 0x3D)) {
            const char: u8 = @truncate(load_reg(psx.cpu.regs, .a0));

            var stdout_buffer: [1024]u8 = undefined;
            var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
            const stdout = &stdout_writer.interface;

            stdout.print("{c}", .{char}) catch |err| {
                std.debug.print("Error writing to stdout: {}\n", .{err});
            };
            stdout.flush() catch unreachable;
        }
    }

    psx.cpu.regs.current_instruction_pc = psx.cpu.regs.pc;

    if (psx.cpu.regs.pc % 4 != 0) {
        execute_exception_bad_address(psx, .AdEL, psx.cpu.regs.pc);
        return;
    }

    const op_code = bus.load_u32(psx, psx.cpu.regs.pc);

    const instruction = instructions.decode_instruction(op_code);

    psx.cpu.regs.pc = psx.cpu.regs.next_pc;
    psx.cpu.regs.next_pc +%= 4;

    psx.cpu.delay_slot = psx.cpu.branch;
    psx.cpu.branch = false;

    if ((psx.cpu.regs.sr.interrupt_stack.current.enabled) and (@as(u3, @bitCast(psx.cpu.regs.cause.interrupt_pending)) & psx.cpu.regs.sr.interrupt_mask) != 0) {
        execute_exception(psx, .INT);
    } else {
        if (config.enable_debug_print) {
            debug.print_instruction_with_pc_decorations(instruction, psx.cpu.regs.current_instruction_pc);
        }

        execute_instruction(psx, instruction);
    }
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
    return load_reg_generic(u32, registers, register_name);
}

fn load_reg_signed(registers: Registers, register_name: cpu.RegisterName) i32 {
    return load_reg_generic(i32, registers, register_name);
}

fn load_reg_generic(load_type: type, registers: Registers, register_name: cpu.RegisterName) load_type {
    const value = switch (register_name) {
        .zero => 0,
        else => registers.gprs[@intFromEnum(register_name)],
    };

    if (config.enable_debug_print) {
        std.debug.print("reg load 0x{x:0>8} from {}\n", .{ value, register_name });
    }

    return @bitCast(value);
}

fn store_reg(registers: *Registers, register_name: cpu.RegisterName, value: u32) void {
    store_reg_generic(registers, register_name, value);
}

fn store_reg_signed(registers: *Registers, register_name: cpu.RegisterName, value: i32) void {
    store_reg_generic(registers, register_name, value);
}

fn store_reg_generic(registers: *Registers, register_name: cpu.RegisterName, value: anytype) void {
    if (config.enable_debug_print) {
        std.debug.print("reg store 0x{x:0>8} in {}\n", .{ value, register_name });
    }

    switch (register_name) {
        .zero => {},
        else => registers.gprs[@intFromEnum(register_name)] = @bitCast(value),
    }
}

fn execute_sll(psx: *PSXState, instruction: instructions.sll) void {
    const value = load_reg(psx.cpu.regs, instruction.rt);

    const result = value << instruction.shift_imm;

    execute_delayed_load(psx);

    store_reg(&psx.cpu.regs, instruction.rd, result);
}

fn execute_srl(psx: *PSXState, instruction: instructions.srl) void {
    const value = load_reg(psx.cpu.regs, instruction.rt);

    const result = value >> instruction.shift_imm;

    execute_delayed_load(psx);

    store_reg(&psx.cpu.regs, instruction.rd, result);
}

fn execute_sra(psx: *PSXState, instruction: instructions.sra) void {
    const value = load_reg_signed(psx.cpu.regs, instruction.rt);

    // Sign-extending
    const result = value >> instruction.shift_imm;

    execute_delayed_load(psx);

    store_reg_signed(&psx.cpu.regs, instruction.rd, result);
}

fn execute_sllv(psx: *PSXState, instruction: instructions.sllv) void {
    const value = load_reg(psx.cpu.regs, instruction.rt);
    const shift: u5 = @truncate(load_reg(psx.cpu.regs, instruction.rs));

    const result = value << shift;

    execute_delayed_load(psx);

    store_reg(&psx.cpu.regs, instruction.rd, result);
}

fn execute_srlv(psx: *PSXState, instruction: instructions.srlv) void {
    const value = load_reg(psx.cpu.regs, instruction.rt);
    const shift: u5 = @truncate(load_reg(psx.cpu.regs, instruction.rs));

    const result = value >> shift;

    execute_delayed_load(psx);

    store_reg(&psx.cpu.regs, instruction.rd, result);
}

fn execute_srav(psx: *PSXState, instruction: instructions.srav) void {
    const value = load_reg_signed(psx.cpu.regs, instruction.rt);
    const shift: u5 = @truncate(load_reg(psx.cpu.regs, instruction.rs));

    // Sign-extending
    const result = value >> shift;

    execute_delayed_load(psx);

    store_reg_signed(&psx.cpu.regs, instruction.rd, result);
}

fn execute_jr(psx: *PSXState, instruction: instructions.jr) void {
    const jump_address = load_reg(psx.cpu.regs, instruction.rs);

    psx.cpu.regs.next_pc = jump_address;
    psx.cpu.branch = true;

    execute_delayed_load(psx);
}

fn execute_jalr(psx: *PSXState, instruction: instructions.jalr) void {
    const jump_address = load_reg(psx.cpu.regs, instruction.rs);
    const return_address = psx.cpu.regs.next_pc;

    psx.cpu.regs.next_pc = jump_address;
    psx.cpu.branch = true;

    execute_delayed_load(psx);

    store_reg(&psx.cpu.regs, instruction.rd, return_address);
}

fn execute_syscall(psx: *PSXState) void {
    execute_exception(psx, .SysCall);
}

fn execute_break(psx: *PSXState) void {
    execute_exception(psx, .BP);
}

fn execute_mult(psx: *PSXState, instruction: instructions.mult) void {
    const a: i64 = load_reg_signed(psx.cpu.regs, instruction.rs);
    const b: i64 = load_reg_signed(psx.cpu.regs, instruction.rt);

    const result: u64 = @bitCast(a * b);

    psx.cpu.regs.hi = @truncate(result >> 32);
    psx.cpu.regs.lo = @truncate(result);

    execute_delayed_load(psx);
}

fn execute_multu(psx: *PSXState, instruction: instructions.multu) void {
    const a: u64 = load_reg(psx.cpu.regs, instruction.rs);
    const b: u64 = load_reg(psx.cpu.regs, instruction.rt);

    const result = a * b;

    psx.cpu.regs.hi = @truncate(result >> 32);
    psx.cpu.regs.lo = @truncate(result);

    execute_delayed_load(psx);
}

fn execute_div(psx: *PSXState, instruction: instructions.div) void {
    const numerator_u32 = load_reg(psx.cpu.regs, instruction.rs);
    const numerator: i32 = @bitCast(numerator_u32);
    const divisor = load_reg_signed(psx.cpu.regs, instruction.rt);

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

    execute_delayed_load(psx);
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

    execute_delayed_load(psx);
}

fn execute_add(psx: *PSXState, instruction: instructions.add) void {
    const value_s = load_reg_signed(psx.cpu.regs, instruction.rs);
    const value_t = load_reg_signed(psx.cpu.regs, instruction.rt);

    const result, const overflow = @addWithOverflow(value_s, value_t);

    execute_delayed_load(psx);

    if (overflow == 1) {
        execute_exception(psx, .Ov);
    } else {
        store_reg_signed(&psx.cpu.regs, instruction.rd, result);
    }
}

fn execute_addu(psx: *PSXState, instruction: instructions.addu) void {
    const value_s = load_reg(psx.cpu.regs, instruction.rs);
    const value_t = load_reg(psx.cpu.regs, instruction.rt);

    const result = value_s +% value_t;

    execute_delayed_load(psx);

    store_reg(&psx.cpu.regs, instruction.rd, result);
}

fn execute_sub(psx: *PSXState, instruction: instructions.sub) void {
    const value_s = load_reg_signed(psx.cpu.regs, instruction.rs);
    const value_t = load_reg_signed(psx.cpu.regs, instruction.rt);

    const result, const overflow = @subWithOverflow(value_s, value_t);

    execute_delayed_load(psx);

    if (overflow == 1) {
        execute_exception(psx, .Ov);
    } else {
        store_reg_signed(&psx.cpu.regs, instruction.rd, result);
    }
}

fn execute_subu(psx: *PSXState, instruction: instructions.subu) void {
    const value_s = load_reg(psx.cpu.regs, instruction.rs);
    const value_t = load_reg(psx.cpu.regs, instruction.rt);

    const result = value_s -% value_t;

    execute_delayed_load(psx);

    store_reg(&psx.cpu.regs, instruction.rd, result);
}

fn execute_and(psx: *PSXState, instruction: instructions.and_) void {
    const value_s = load_reg(psx.cpu.regs, instruction.rs);
    const value_t = load_reg(psx.cpu.regs, instruction.rt);

    execute_delayed_load(psx);

    store_reg(&psx.cpu.regs, instruction.rd, value_s & value_t);
}

fn execute_or(psx: *PSXState, instruction: instructions.or_) void {
    const value_s = load_reg(psx.cpu.regs, instruction.rs);
    const value_t = load_reg(psx.cpu.regs, instruction.rt);

    execute_delayed_load(psx);

    store_reg(&psx.cpu.regs, instruction.rd, value_s | value_t);
}

fn execute_xor(psx: *PSXState, instruction: instructions.xor) void {
    const value_s = load_reg(psx.cpu.regs, instruction.rs);
    const value_t = load_reg(psx.cpu.regs, instruction.rt);

    execute_delayed_load(psx);

    store_reg(&psx.cpu.regs, instruction.rd, value_s ^ value_t);
}

fn execute_nor(psx: *PSXState, instruction: instructions.nor) void {
    const value_s = load_reg(psx.cpu.regs, instruction.rs);
    const value_t = load_reg(psx.cpu.regs, instruction.rt);

    execute_delayed_load(psx);

    store_reg(&psx.cpu.regs, instruction.rd, ~(value_s | value_t));
}

fn execute_slt(psx: *PSXState, instruction: instructions.slt) void {
    const value_s = load_reg_signed(psx.cpu.regs, instruction.rs);
    const value_t = load_reg_signed(psx.cpu.regs, instruction.rt);

    const result: u32 = if (value_s < value_t) 1 else 0;

    execute_delayed_load(psx);

    store_reg(&psx.cpu.regs, instruction.rd, result);
}

fn execute_sltu(psx: *PSXState, instruction: instructions.sltu) void {
    const value_s = load_reg(psx.cpu.regs, instruction.rs);
    const value_t = load_reg(psx.cpu.regs, instruction.rt);

    const result: u32 = if (value_s < value_t) 1 else 0;

    execute_delayed_load(psx);

    store_reg(&psx.cpu.regs, instruction.rd, result);
}

fn execute_b_cond_z(psx: *PSXState, instruction: instructions.b_cond_z) void {
    const value_s = load_reg_signed(psx.cpu.regs, instruction.rs);

    var test_value = value_s < 0;

    // Flip test if needed
    test_value = test_value != instruction.test_greater;

    execute_delayed_load(psx);

    if (instruction.link) {
        store_reg(&psx.cpu.regs, cpu.RegisterName.ra, psx.cpu.regs.next_pc);
    }

    if (test_value) {
        execute_generic_branch(psx, instruction.rel_offset);
    }
}

fn execute_j(psx: *PSXState, instruction: instructions.j) void {
    const jump_address = (psx.cpu.regs.next_pc & 0xf0_00_00_00) | instruction.offset;

    psx.cpu.regs.next_pc = jump_address;
    psx.cpu.branch = true;

    execute_delayed_load(psx);
}

fn execute_jal(psx: *PSXState, instruction: instructions.jal) void {
    const return_address = psx.cpu.regs.next_pc;
    const jump_address = (psx.cpu.regs.next_pc & 0xf0_00_00_00) | instruction.offset;

    psx.cpu.regs.next_pc = jump_address;
    psx.cpu.branch = true;

    execute_delayed_load(psx);

    store_reg(&psx.cpu.regs, cpu.RegisterName.ra, return_address);
}

fn execute_beq(psx: *PSXState, instruction: instructions.beq) void {
    const value_s = load_reg(psx.cpu.regs, instruction.rs);
    const value_t = load_reg(psx.cpu.regs, instruction.rt);

    if (value_s == value_t) {
        execute_generic_branch(psx, instruction.rel_offset);
    }

    execute_delayed_load(psx);
}

fn execute_bne(psx: *PSXState, instruction: instructions.bne) void {
    const value_s = load_reg(psx.cpu.regs, instruction.rs);
    const value_t = load_reg(psx.cpu.regs, instruction.rt);

    if (value_s != value_t) {
        execute_generic_branch(psx, instruction.rel_offset);
    }

    execute_delayed_load(psx);
}

fn execute_blez(psx: *PSXState, instruction: instructions.blez) void {
    const value_s = load_reg_signed(psx.cpu.regs, instruction.rs);

    if (value_s <= 0) {
        execute_generic_branch(psx, instruction.rel_offset);
    }

    execute_delayed_load(psx);
}

fn execute_bgtz(psx: *PSXState, instruction: instructions.bgtz) void {
    const value_s = load_reg_signed(psx.cpu.regs, instruction.rs);

    if (value_s > 0) {
        execute_generic_branch(psx, instruction.rel_offset);
    }

    execute_delayed_load(psx);
}

fn execute_mfc(psx: *PSXState, instruction: instructions.mtc) void {
    switch (instruction.target) {
        .cop0 => |cop0_target| {
            const value: u32 = switch (cop0_target) {
                .BPC, .BDA, .BDAM, .BPCM => {
                    std.debug.print("mfc0 target read ignored: {}\n", .{instruction.target});
                    unreachable; // FIXME These are not implemented yet
                },
                .DCIC => 0, // FIXME
                .JUMPDEST => 0, // FIXME
                .BadVaddr => psx.cpu.regs.bad_vaddr,
                .SR => @bitCast(psx.cpu.regs.sr),
                .CAUSE => @bitCast(psx.cpu.regs.cause),
                .EPC => psx.cpu.regs.epc,
                .PRID => cpu.CPU_PRID,
                _ => unreachable,
            };

            execute_chained_delay_load(psx, instruction.cpu_rs, value);
        },
        .cop2 => unreachable, // FIXME
        .cop1 => @panic("mfc1 is not valid"),
        .cop3 => @panic("mfc3 is not valid"),
    }
}

fn execute_cfc(psx: *PSXState, instruction: instructions.cfc) void {
    _ = psx;
    _ = instruction;
    unreachable;
}

fn execute_mtc(psx: *PSXState, instruction: instructions.mtc) void {
    const value = load_reg(psx.cpu.regs, instruction.cpu_rs);

    switch (instruction.target) {
        .cop0 => |cop0_target| {
            switch (cop0_target) {
                .BPC, .BDA, .JUMPDEST, .DCIC, .BadVaddr, .BDAM, .BPCM, .PRID => {
                    if (config.enable_debug_print) {
                        std.debug.print("FIXME mtc0 target write ignored\n", .{});
                    }
                },
                .SR => psx.cpu.regs.sr = @bitCast(value),
                .CAUSE => {
                    const cause_new: @TypeOf(psx.cpu.regs.cause) = @bitCast(value);

                    // Only those two bits are R/W
                    psx.cpu.regs.cause.interrupt_pending.software_irq0 = cause_new.interrupt_pending.software_irq0;
                    psx.cpu.regs.cause.interrupt_pending.software_irq1 = cause_new.interrupt_pending.software_irq1;
                },
                .EPC => unreachable,
                _ => {
                    std.debug.print("mtc0 target: {}\n", .{instruction.target});
                    unreachable;
                },
            }
        },
        .cop2 => unreachable, // FIXME
        .cop1 => @panic("mtc1 is not valid"),
        .cop3 => @panic("mtc3 is not valid"),
    }
}

fn execute_ctc(psx: *PSXState, instruction: instructions.ctc) void {
    const value = load_reg(psx.cpu.regs, instruction.cpu_rs);

    switch (instruction.target) {
        .cop0 => unreachable, // FIXME
        .cop2 => |register_index| {
            gte.execute_ctc(psx, register_index, value);
        }, // FIXME
        .cop1 => @panic("ctc1 is not valid"),
        .cop3 => @panic("ctc3 is not valid"),
    }
}

fn execute_bcn(psx: *PSXState, instruction: instructions.bcn) void {
    _ = psx;
    _ = instruction;
    unreachable;
}

fn execute_addi(psx: *PSXState, instruction: instructions.addi) void {
    const value_s = load_reg_signed(psx.cpu.regs, instruction.rs);
    const value_imm: i32 = instruction.imm_i16;

    const result, const overflow = @addWithOverflow(value_s, value_imm);

    execute_delayed_load(psx);

    if (overflow == 1) {
        execute_exception(psx, .Ov);
    } else {
        store_reg_signed(&psx.cpu.regs, instruction.rt, result);
    }
}

fn execute_addiu(psx: *PSXState, instruction: instructions.addiu) void {
    const value_s = load_reg(psx.cpu.regs, instruction.rs);

    const result = wrapping_add_u32_i32(value_s, instruction.imm_i16);

    execute_delayed_load(psx);

    store_reg(&psx.cpu.regs, instruction.rt, result);
}

fn execute_slti(psx: *PSXState, instruction: instructions.slti) void {
    const value_s = load_reg_signed(psx.cpu.regs, instruction.rs);

    const result: u32 = if (value_s < instruction.imm_i16) 1 else 0;

    execute_delayed_load(psx);

    store_reg(&psx.cpu.regs, instruction.rt, result);
}

fn execute_sltiu(psx: *PSXState, instruction: instructions.sltiu) void {
    const value_s = load_reg(psx.cpu.regs, instruction.rs);
    const imm_se: u32 = @bitCast(@as(i32, instruction.imm_i16)); // Super weird behavior

    const result: u32 = if (value_s < imm_se) 1 else 0;

    execute_delayed_load(psx);

    store_reg(&psx.cpu.regs, instruction.rt, result);
}

fn execute_andi(psx: *PSXState, instruction: instructions.andi) void {
    const value = load_reg(psx.cpu.regs, instruction.rs);

    execute_delayed_load(psx);

    store_reg(&psx.cpu.regs, instruction.rt, value & instruction.imm_u16);
}

fn execute_ori(psx: *PSXState, instruction: instructions.ori) void {
    const value = load_reg(psx.cpu.regs, instruction.rs);

    execute_delayed_load(psx);

    store_reg(&psx.cpu.regs, instruction.rt, value | instruction.imm_u16);
}

fn execute_xori(psx: *PSXState, instruction: instructions.xori) void {
    const value = load_reg(psx.cpu.regs, instruction.rs);

    execute_delayed_load(psx);

    store_reg(&psx.cpu.regs, instruction.rt, value ^ instruction.imm_u16);
}

fn execute_lui(psx: *PSXState, instruction: instructions.lui) void {
    const value = @as(u32, instruction.imm_u16) << 16;

    execute_delayed_load(psx);

    store_reg(&psx.cpu.regs, instruction.rt, value);
}

fn execute_lb(psx: *PSXState, instruction: instructions.lb) void {
    const address_base = load_reg(psx.cpu.regs, instruction.rs);
    const address = wrapping_add_u32_i32(address_base, instruction.imm_i16);

    const value: i8 = @bitCast(bus.load_u8(psx, address));
    const value_sign_extended: i32 = value;

    execute_chained_delay_load(psx, instruction.rt, @bitCast(value_sign_extended));
}

fn execute_lbu(psx: *PSXState, instruction: instructions.lbu) void {
    const address_base = load_reg(psx.cpu.regs, instruction.rs);
    const address = wrapping_add_u32_i32(address_base, instruction.imm_i16);

    const value: u8 = bus.load_u8(psx, address);

    execute_chained_delay_load(psx, instruction.rt, value);
}

fn execute_lh(psx: *PSXState, instruction: instructions.lh) void {
    const address_base = load_reg(psx.cpu.regs, instruction.rs);
    const address = wrapping_add_u32_i32(address_base, instruction.imm_i16);

    if (address % 2 == 0) {
        const value: i16 = @bitCast(bus.load_u16(psx, address));
        const value_sign_extended: i32 = value;

        execute_chained_delay_load(psx, instruction.rt, @bitCast(value_sign_extended));
    } else {
        execute_delayed_load(psx);
        execute_exception_bad_address(psx, .AdEL, address);
    }
}

fn execute_lhu(psx: *PSXState, instruction: instructions.lhu) void {
    const address_base = load_reg(psx.cpu.regs, instruction.rs);
    const address = wrapping_add_u32_i32(address_base, instruction.imm_i16);

    if (address % 2 == 0) {
        const value = bus.load_u16(psx, address);

        execute_chained_delay_load(psx, instruction.rt, value);
    } else {
        execute_delayed_load(psx);
        execute_exception_bad_address(psx, .AdEL, address);
    }
}

fn execute_lw(psx: *PSXState, instruction: instructions.lw) void {
    const address_base = load_reg(psx.cpu.regs, instruction.rs);
    const address = wrapping_add_u32_i32(address_base, instruction.imm_i16);

    if (address % 4 == 0) {
        const value = bus.load_u32(psx, address);

        execute_chained_delay_load(psx, instruction.rt, value);
    } else {
        execute_delayed_load(psx);
        execute_exception_bad_address(psx, .AdEL, address);
    }
}

const UnalignedType = enum {
    Left,
    Right,
};

fn execute_lwl(psx: *PSXState, instruction: instructions.lwl) void {
    execute_lw_unaligned(psx, instruction, .Left);
}

fn execute_lwr(psx: *PSXState, instruction: instructions.lwr) void {
    execute_lw_unaligned(psx, instruction, .Right);
}

fn execute_lw_unaligned(psx: *PSXState, instruction: instructions.lwl, direction: UnalignedType) void {
    const address_base = load_reg(psx.cpu.regs, instruction.rs);
    const address = wrapping_add_u32_i32(address_base, instruction.imm_i16);
    const address_aligned = address & ~@as(u32, 0b11);

    const load_value = bus.load_u32(psx, address_aligned);

    var previous_value = load_reg(psx.cpu.regs, instruction.rt);

    if (psx.cpu.regs.pending_load) |pending_load| {
        if (pending_load.register == instruction.rt) {
            previous_value = pending_load.value;
        }
    }

    const result = switch (direction) {
        .Left => switch (address % 4) {
            0 => previous_value & 0x00_ff_ff_ff | load_value << 24,
            1 => previous_value & 0x00_00_ff_ff | load_value << 16,
            2 => previous_value & 0x00_00_00_ff | load_value << 8,
            3 => previous_value & 0x00_00_00_00 | load_value << 0,
            else => unreachable,
        },
        .Right => switch (address % 4) {
            0 => previous_value & 0x00_00_00_00 | load_value >> 0,
            1 => previous_value & 0xff_00_00_00 | load_value >> 8,
            2 => previous_value & 0xff_ff_00_00 | load_value >> 16,
            3 => previous_value & 0xff_ff_ff_00 | load_value >> 24,
            else => unreachable,
        },
    };

    execute_chained_delay_load(psx, instruction.rt, result);
}

fn execute_sb(psx: *PSXState, instruction: instructions.sb) void {
    const value = load_reg(psx.cpu.regs, instruction.rt);

    const address_base = load_reg(psx.cpu.regs, instruction.rs);
    const address = wrapping_add_u32_i32(address_base, instruction.imm_i16);

    execute_delayed_load(psx);

    bus.store_u8(psx, address, @truncate(value));
}

fn execute_sh(psx: *PSXState, instruction: instructions.sh) void {
    const value = load_reg(psx.cpu.regs, instruction.rt);

    const address_base = load_reg(psx.cpu.regs, instruction.rs);
    const address = wrapping_add_u32_i32(address_base, instruction.imm_i16);

    execute_delayed_load(psx);

    if (address % 2 == 0) {
        bus.store_u16(psx, address, @truncate(value));
    } else {
        execute_exception_bad_address(psx, .AdES, address);
    }
}

fn execute_sw(psx: *PSXState, instruction: instructions.sw) void {
    const value = load_reg(psx.cpu.regs, instruction.rt);

    const address_base = load_reg(psx.cpu.regs, instruction.rs);
    const address = wrapping_add_u32_i32(address_base, instruction.imm_i16);

    execute_delayed_load(psx);

    if (address % 4 == 0) {
        bus.store_u32(psx, address, value);
    } else {
        execute_exception_bad_address(psx, .AdES, address);
    }
}

fn execute_swl(psx: *PSXState, instruction: instructions.swl) void {
    execute_sw_unaligned(psx, instruction, .Left);
}

fn execute_swr(psx: *PSXState, instruction: instructions.swr) void {
    execute_sw_unaligned(psx, instruction, .Right);
}

fn execute_sw_unaligned(psx: *PSXState, instruction: instructions.swl, direction: UnalignedType) void {
    const value = load_reg(psx.cpu.regs, instruction.rt);

    const address_base = load_reg(psx.cpu.regs, instruction.rs);
    const address = wrapping_add_u32_i32(address_base, instruction.imm_i16);
    const address_aligned = address & ~@as(u32, 0b11);

    const previous_value = bus.load_u32(psx, address_aligned);

    const result = switch (direction) {
        .Left => switch (address % 4) {
            0 => previous_value & 0xff_ff_ff_00 | value >> 24,
            1 => previous_value & 0xff_ff_00_00 | value >> 16,
            2 => previous_value & 0xff_00_00_00 | value >> 8,
            3 => previous_value & 0x00_00_00_00 | value >> 0,
            else => unreachable,
        },
        .Right => switch (address % 4) {
            0 => previous_value & 0x00_00_00_00 | value << 0,
            1 => previous_value & 0x00_00_00_ff | value << 8,
            2 => previous_value & 0x00_00_ff_ff | value << 16,
            3 => previous_value & 0x00_ff_ff_ff | value << 24,
            else => unreachable,
        },
    };

    execute_delayed_load(psx);

    bus.store_u32(psx, address_aligned, result);
}

fn execute_mfhi(psx: *PSXState, instruction: instructions.mfhi) void {
    execute_delayed_load(psx);

    store_reg(&psx.cpu.regs, instruction.rd, psx.cpu.regs.hi);
}

fn execute_mthi(psx: *PSXState, instruction: instructions.mthi) void {
    psx.cpu.regs.hi = load_reg(psx.cpu.regs, instruction.rs);

    execute_delayed_load(psx);
}

fn execute_mflo(psx: *PSXState, instruction: instructions.mflo) void {
    execute_delayed_load(psx);

    store_reg(&psx.cpu.regs, instruction.rd, psx.cpu.regs.lo);
}

fn execute_mtlo(psx: *PSXState, instruction: instructions.mtlo) void {
    psx.cpu.regs.lo = load_reg(psx.cpu.regs, instruction.rs);

    execute_delayed_load(psx);
}

fn execute_rfe(psx: *PSXState) void {
    execute_delayed_load(psx);

    execute_interrupt_stack_pop(psx);
}

fn execute_cop1(psx: *PSXState) void {
    execute_delayed_load(psx);

    execute_exception(psx, .CpU);
}

fn execute_cop2(psx: *PSXState) void {
    _ = psx;
    unreachable;
}

fn execute_cop3(psx: *PSXState) void {
    execute_delayed_load(psx);

    execute_exception(psx, .CpU);
}

fn execute_lwc(psx: *PSXState, instruction: instructions.lwc) void {
    execute_delayed_load(psx); // FIXME

    if (instruction.cop_index == 2) {
        unreachable;
    } else {
        execute_exception(psx, .CpU);
    }
}

fn execute_swc(psx: *PSXState, instruction: instructions.swc) void {
    execute_delayed_load(psx); // FIXME

    if (instruction.cop_index == 2) {
        unreachable;
    } else {
        execute_exception(psx, .CpU);
    }
}

fn execute_reserved_instruction(psx: *PSXState) void {
    execute_delayed_load(psx);

    execute_exception(psx, .RI);
}

// Most instructions need to execute this BEFORE writing to a register to that they can take precendence.
// Most instruction also need to execute this AFTER reading to a register to get the correct value.
// NOTE Currently the later condition is not needed because we double-buffer register values, but maybe we actually shouldn't for perf.
fn execute_delayed_load(psx: *PSXState) void {
    if (psx.cpu.regs.pending_load) |pending_load| {
        store_reg(&psx.cpu.regs, pending_load.register, pending_load.value);
        psx.cpu.regs.pending_load = null;
    }
}

fn execute_chained_delay_load(psx: *PSXState, register_name: cpu.RegisterName, value: u32) void {
    if (psx.cpu.regs.pending_load) |pending_load| {
        if (pending_load.register != register_name) {
            store_reg(&psx.cpu.regs, pending_load.register, pending_load.value);
        }
    }

    psx.cpu.regs.pending_load = .{ .register = register_name, .value = value };
}

fn execute_generic_branch(psx: *PSXState, offset: i32) void {
    psx.cpu.regs.next_pc = wrapping_add_u32_i32(psx.cpu.regs.pc, offset);
    psx.cpu.branch = true;
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

fn execute_exception_bad_address(psx: *PSXState, cause: cpu.ExceptionCause, address: u32) void {
    std.debug.assert(cause == .AdES or cause == .AdEL);
    psx.cpu.regs.bad_vaddr = address;

    execute_exception(psx, cause);
}

fn execute_exception(psx: *PSXState, cause: cpu.ExceptionCause) void {
    if (config.enable_debug_print) {
        std.debug.print("Exception: {}\n", .{cause});
    }

    psx.cpu.regs.cause = @bitCast(@as(u32, 0));
    psx.cpu.regs.cause.cause = cause;
    psx.cpu.regs.cause.branch_delay = if (psx.cpu.delay_slot) 1 else 0;

    psx.cpu.regs.epc = psx.cpu.regs.current_instruction_pc;

    if (psx.cpu.delay_slot) {
        psx.cpu.regs.epc -%= 4;
    }

    psx.cpu.regs.pc = if (psx.cpu.regs.sr.bev == 1) 0xbfc00180 else 0x80000080;
    psx.cpu.regs.next_pc = psx.cpu.regs.pc +% 4;

    execute_interrupt_stack_push(psx);
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
