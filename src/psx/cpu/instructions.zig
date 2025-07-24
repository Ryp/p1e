const std = @import("std");

const cpu = @import("state.zig");

// Opcode/Parameter Encoding
//
//   31..26 |25..21|20..16|15..11|10..6 |  5..0  |
//    6bit  | 5bit | 5bit | 5bit | 5bit |  6bit  |
//   -------+------+------+------+------+--------+------------
//   000000 | N/A  | rt   | rd   | imm5 | 0000xx | shift-imm
//   000000 | rs   | rt   | rd   | N/A  | 0001xx | shift-reg
//   000000 | rs   | N/A  | N/A  | N/A  | 001000 | jr
//   000000 | rs   | N/A  | rd   | N/A  | 001001 | jalr
//   000000 | <-----comment20bit------> | 00110x | sys/brk
//   000000 | N/A  | N/A  | rd   | N/A  | 0100x0 | mfhi/mflo
//   000000 | rs   | N/A  | N/A  | N/A  | 0100x1 | mthi/mtlo
//   000000 | rs   | rt   | N/A  | N/A  | 0110xx | mul/div
//   000000 | rs   | rt   | rd   | N/A  | 10xxxx | alu-reg
//   000001 | rs   | 00000| <--immediate16bit--> | bltz
//   000001 | rs   | 00001| <--immediate16bit--> | bgez
//   000001 | rs   | 10000| <--immediate16bit--> | bltzal
//   000001 | rs   | 10001| <--immediate16bit--> | bgezal
//   000001 | rs   | xxxx0| <--immediate16bit--> | bltz  ;\undocumented dupes
//   000001 | rs   | xxxx1| <--immediate16bit--> | bgez  ;/(when bit17-19=nonzero)
//   00001x | <---------immediate26bit---------> | j/jal
//   00010x | rs   | rt   | <--immediate16bit--> | beq/bne
//   00011x | rs   | N/A  | <--immediate16bit--> | blez/bgtz
//   001xxx | rs   | rt   | <--immediate16bit--> | alu-imm
//   001111 | N/A  | rt   | <--immediate16bit--> | lui-imm
//   100xxx | rs   | rt   | <--immediate16bit--> | load rt,[rs+imm]
//   101xxx | rs   | rt   | <--immediate16bit--> | store rt,[rs+imm]
//   x1xxxx | <------coprocessor specific------> | coprocessor (see below)
const OpCodeHelper = packed struct {
    b0_15: packed union {
        encoding_a: packed struct {
            secondary: SecondaryOpCode,
            imm5: u5,
            rd: cpu.RegisterName,
        },
        encoding_b: packed struct {
            imm16: u16,
        },
    },
    rt: cpu.RegisterName,
    rs: cpu.RegisterName,
    primary: PrimaryOpCode,
};

comptime {
    std.debug.assert(@sizeOf(OpCodeHelper) == 4);
}

// NOTE: names with '_' in the name clash with zig builtins
pub const Instruction = union(enum) {
    sll: sll,
    srl: srl,
    sra: sra,
    sllv: sllv,
    srlv: srlv,
    srav: srav,
    jr: jr,
    jalr: jalr,
    syscall,
    break_,
    mfhi: mfhi,
    mthi: mthi,
    mflo: mflo,
    mtlo: mtlo,
    mult: mult,
    multu: multu,
    div: div,
    divu: divu,
    add: add,
    addu: addu,
    sub: sub,
    subu: subu,
    and_: and_,
    or_: or_,
    xor: xor,
    nor: nor,
    slt: slt,
    sltu: sltu,
    b_cond_z: b_cond_z,
    j: j,
    jal: jal,
    beq: beq,
    bne: bne,
    blez: blez,
    bgtz: bgtz,
    mfc: mfc,
    cfc: cfc,
    mtc: mtc,
    ctc: ctc,
    bcn: bcn,
    rfe,
    cop1,
    cop2,
    cop3,
    addi: addi,
    addiu: addiu,
    slti: slti,
    sltiu: sltiu,
    andi: andi,
    ori: ori,
    xori: xori,
    lui: lui,
    lb: lb,
    lh: lh,
    lwl: lwl,
    lw: lw,
    lbu: lbu,
    lhu: lhu,
    lwr: lwr,
    sb: sb,
    sh: sh,
    swl: swl,
    sw: sw,
    swr: swr,
    lwc: lwc,
    swc: swc,
    invalid,
};

pub fn decode_instruction(op_u32: u32) Instruction {
    const op: OpCodeHelper = @bitCast(op_u32);

    return switch (op.primary) {
        .SPECIAL => switch (op.b0_15.encoding_a.secondary) {
            .SLL => .{ .sll = decode_generic_shift_imm(op_u32) },
            .SRL => .{ .srl = decode_generic_shift_imm(op_u32) },
            .SRA => .{ .sra = decode_generic_shift_imm(op_u32) },
            .SLLV => .{ .sllv = decode_generic_rs_rt_rd(op_u32) },
            .SRLV => .{ .srlv = decode_generic_rs_rt_rd(op_u32) },
            .SRAV => .{ .srav = decode_generic_rs_rt_rd(op_u32) },

            .JR => .{ .jr = .{ .rs = op.rs } },
            .JALR => .{ .jalr = .{ .rs = op.rs, .rd = op.b0_15.encoding_a.rd } },
            .SYSCALL => .{ .syscall = undefined },
            .BREAK => .{ .break_ = undefined },

            .MFHI => .{ .mfhi = decode_generic_rd(op_u32) },
            .MTHI => .{ .mthi = decode_generic_rs(op_u32) },
            .MFLO => .{ .mflo = decode_generic_rd(op_u32) },
            .MTLO => .{ .mtlo = decode_generic_rs(op_u32) },

            .MULT => .{ .mult = decode_generic_rs_rt(op_u32) },
            .MULTU => .{ .multu = decode_generic_rs_rt(op_u32) },
            .DIV => .{ .div = decode_generic_rs_rt(op_u32) },
            .DIVU => .{ .divu = decode_generic_rs_rt(op_u32) },

            .ADD => .{ .add = decode_generic_rs_rt_rd(op_u32) },
            .ADDU => .{ .addu = decode_generic_rs_rt_rd(op_u32) },
            .SUB => .{ .sub = decode_generic_rs_rt_rd(op_u32) },
            .SUBU => .{ .subu = decode_generic_rs_rt_rd(op_u32) },
            .AND => .{ .and_ = decode_generic_rs_rt_rd(op_u32) },
            .OR => .{ .or_ = decode_generic_rs_rt_rd(op_u32) },
            .XOR => .{ .xor = decode_generic_rs_rt_rd(op_u32) },
            .NOR => .{ .nor = decode_generic_rs_rt_rd(op_u32) },

            .SLT => .{ .slt = decode_generic_rs_rt_rd(op_u32) },
            .SLTU => .{ .sltu = decode_generic_rs_rt_rd(op_u32) },
            _ => .{ .invalid = undefined },
        },
        .BcondZ => .{ .b_cond_z = decode_b_cond_z(op_u32) },
        .J => .{ .j = decode_generic_j(op_u32) },
        .JAL => .{ .jal = decode_generic_j(op_u32) },
        .BEQ => .{ .beq = decode_generic_branch(op_u32) },
        .BNE => .{ .bne = decode_generic_branch(op_u32) },
        .BLEZ => .{ .blez = decode_generic_branch_2(op_u32) },
        .BGTZ => .{ .bgtz = decode_generic_branch_2(op_u32) },
        .ADDI => .{ .addi = decode_generic_rs_rt_imm_i16(op_u32) },
        .ADDIU => .{ .addiu = decode_generic_rs_rt_imm_i16(op_u32) },
        .SLTI => .{ .slti = decode_generic_rs_rt_imm_i16(op_u32) },
        .SLTIU => .{ .sltiu = decode_generic_rs_rt_imm_i16(op_u32) },
        .ANDI => .{ .andi = decode_generic_rs_rt_imm_u16(op_u32) },
        .ORI => .{ .ori = decode_generic_rs_rt_imm_u16(op_u32) },
        .XORI => .{ .xori = decode_generic_rs_rt_imm_u16(op_u32) },
        .LUI => .{ .lui = decode_generic_rt_imm_u16(op_u32) },
        .COP0, .COP1, .COP2, .COP3 => decode_cop_instruction(@bitCast(op_u32)),
        .LB => .{ .lb = decode_generic_rs_rt_imm_i16(op_u32) },
        .LH => .{ .lh = decode_generic_rs_rt_imm_i16(op_u32) },
        .LWL => .{ .lwl = decode_generic_rs_rt_imm_i16(op_u32) },
        .LW => .{ .lw = decode_generic_rs_rt_imm_i16(op_u32) },
        .LBU => .{ .lbu = decode_generic_rs_rt_imm_i16(op_u32) },
        .LHU => .{ .lhu = decode_generic_rs_rt_imm_i16(op_u32) },
        .LWR => .{ .lwr = decode_generic_rs_rt_imm_i16(op_u32) },
        .SB => .{ .sb = decode_generic_rs_rt_imm_i16(op_u32) },
        .SH => .{ .sh = decode_generic_rs_rt_imm_i16(op_u32) },
        .SWL => .{ .swl = decode_generic_rs_rt_imm_i16(op_u32) },
        .SW => .{ .sw = decode_generic_rs_rt_imm_i16(op_u32) },
        .SWR => .{ .swr = decode_generic_rs_rt_imm_i16(op_u32) },
        .LWC0, .LWC1, .LWC2, .LWC3 => .{ .lwc = decode_generic_cop_load_store(op_u32) },
        .SWC0, .SWC1, .SWC2, .SWC3 => .{ .swc = decode_generic_cop_load_store(op_u32) },
        _ => .{ .invalid = undefined },
    };
}

const PrimaryOpCode = enum(u6) {
    SPECIAL = 0x00,
    BcondZ = 0x01,
    J = 0x02,
    JAL = 0x03,
    BEQ = 0x04,
    BNE = 0x05,
    BLEZ = 0x06,
    BGTZ = 0x07,
    ADDI = 0x08,
    ADDIU = 0x09,
    SLTI = 0x0A,
    SLTIU = 0x0B,
    ANDI = 0x0C,
    ORI = 0x0D,
    XORI = 0x0E,
    LUI = 0x0F,
    COP0 = 0x10,
    COP1 = 0x11,
    COP2 = 0x12,
    COP3 = 0x13,

    LB = 0x20,
    LH = 0x21,
    LWL = 0x22,
    LW = 0x23,
    LBU = 0x24,
    LHU = 0x25,
    LWR = 0x26,

    SB = 0x28,
    SH = 0x29,
    SWL = 0x2A,
    SW = 0x2B,

    SWR = 0x2E,

    LWC0 = 0x30,
    LWC1 = 0x31,
    LWC2 = 0x32,
    LWC3 = 0x33,

    SWC0 = 0x38,
    SWC1 = 0x39,
    SWC2 = 0x3A,
    SWC3 = 0x3B,
    _,
};

const SecondaryOpCode = enum(u6) {
    SLL = 0x00,

    SRL = 0x02,
    SRA = 0x03,
    SLLV = 0x04,

    SRLV = 0x06,
    SRAV = 0x07,
    JR = 0x08,
    JALR = 0x09,

    SYSCALL = 0x0C,
    BREAK = 0x0D,

    MFHI = 0x10,
    MTHI = 0x11,
    MFLO = 0x12,
    MTLO = 0x13,

    MULT = 0x18,
    MULTU = 0x19,
    DIV = 0x1A,
    DIVU = 0x1B,

    ADD = 0x20,
    ADDU = 0x21,
    SUB = 0x22,
    SUBU = 0x23,
    AND = 0x24,
    OR = 0x25,
    XOR = 0x26,
    NOR = 0x27,

    SLT = 0x2A,
    SLTU = 0x2B,
    _,
};

// Coprocessor Opcode/Parameter Encoding
//
//   31..26 |25..21|20..16|15..11|10..6 |  5..0  |
//    6bit  | 5bit | 5bit | 5bit | 5bit |  6bit  |
//   -------+------+------+------+------+--------+------------
//   0100nn |0|0000| rt   | rd   | N/A  | 000000 | MFCn rt,rd_dat  ;rt = dat
//   0100nn |0|0010| rt   | rd   | N/A  | 000000 | CFCn rt,rd_cnt  ;rt = cnt
//   0100nn |0|0100| rt   | rd   | N/A  | 000000 | MTCn rt,rd_dat  ;dat = rt
//   0100nn |0|0110| rt   | rd   | N/A  | 000000 | CTCn rt,rd_cnt  ;cnt = rt
//   0100nn |0|1000|00000 | <--immediate16bit--> | BCnF target ;jump if false
//   0100nn |0|1000|00001 | <--immediate16bit--> | BCnT target ;jump if true
//   0100nn |1| <--------immediate25bit--------> | COPn imm25
//
//   010000 |1|0000| N/A  | N/A  | N/A  | 000001 | COP0 01h  ;=TLBR   ;\if any
//   010000 |1|0000| N/A  | N/A  | N/A  | 000010 | COP0 02h  ;=TLBWI  ; (not on
//   010000 |1|0000| N/A  | N/A  | N/A  | 000110 | COP0 06h  ;=TLBWR  ; psx)
//   010000 |1|0000| N/A  | N/A  | N/A  | 001000 | COP0 08h  ;=TLBP   ;/
//   010000 |1|0000| N/A  | N/A  | N/A  | 010000 | COP0 10h  ;=RFE

const RawCopInstruction = packed struct {
    b0_5: u6,
    b6_10: u5,
    b11_15: u5,
    b16_20: u5,
    b21_24: u4,
    b25: u1,
    cop_index: u2,
    b28_31: u4,
};

fn decode_cop_instruction(op_cop: RawCopInstruction) Instruction {
    if (op_cop.b25 == 0) {
        // Generic ops for all coprocessors
        const op_copn: CopN_OpCode = @enumFromInt(op_cop.b21_24);

        if (op_cop.b0_5 == 0b000000) {
            switch (op_copn) {
                .mfc => return .{ .mfc = .{ .cop_index = op_cop.cop_index, .cpu_rs = @enumFromInt(op_cop.b16_20), .target = @enumFromInt(op_cop.b11_15) } },
                .cfc => return .{ .cfc = .{ .cop_index = op_cop.cop_index, .cpu_rs = @enumFromInt(op_cop.b16_20), .target = @enumFromInt(op_cop.b11_15) } },
                .mtc => return .{ .mtc = .{ .cop_index = op_cop.cop_index, .cpu_rs = @enumFromInt(op_cop.b16_20), .target = @enumFromInt(op_cop.b11_15) } },
                .ctc => return .{ .ctc = .{ .cop_index = op_cop.cop_index, .cpu_rs = @enumFromInt(op_cop.b16_20), .target = @enumFromInt(op_cop.b11_15) } },
                else => return .{ .invalid = undefined },
            }
        }

        if (op_copn == .bc) {
            const imm_u16: u16 = @truncate(@as(u32, @bitCast(op_cop)));

            switch (op_cop.b16_20) {
                0b00000 => return .{ .bcn = .{ .cop_index = op_cop.cop_index, .condition = false, .imm_u16 = imm_u16 } },
                0b00001 => return .{ .bcn = .{ .cop_index = op_cop.cop_index, .condition = true, .imm_u16 = imm_u16 } },
                else => return .{ .invalid = undefined },
            }
        }

        return .{ .invalid = undefined };
    } else {
        switch (op_cop.cop_index) {
            0 => return decode_cop0_instruction(op_cop),
            1 => return .{ .cop1 = undefined },
            2 => return decode_cop2_instruction(op_cop),
            3 => return .{ .cop3 = undefined },
        }
    }
}

fn decode_cop0_instruction(op_cop: RawCopInstruction) Instruction {
    if (op_cop.b21_24 == 0b0000) {
        return switch (op_cop.b0_5) {
            0b000001 => .{ .invalid = undefined }, // TLBR
            0b000010 => .{ .invalid = undefined }, // TLBWI
            0b000110 => .{ .invalid = undefined }, // TLBWR
            0b001000 => .{ .invalid = undefined }, // TLBP
            0b010000 => .{ .rfe = undefined },
            else => .{ .invalid = undefined },
        };
    } else {
        return .{ .invalid = undefined };
    }
}

fn decode_cop2_instruction(op_cop: RawCopInstruction) Instruction {
    _ = op_cop; // FIXME
    return .{ .cop2 = undefined };
}

const CopN_OpCode = enum(u4) {
    mfc = 0b0000,
    cfc = 0b0010,
    mtc = 0b0100,
    ctc = 0b0110,
    bc = 0b1000,
    _,
};

const Cop0RegisterName = enum(u5) {
    BPC = 3, // Breakpoint on execute (R/W)
    BDA = 5, // Breakpoint on data access (R/W)
    JUMPDEST = 6, // Randomly memorized jump address (R)
    DCIC = 7, // Breakpoint control (R/W)
    BadVaddr = 8, // Bad Virtual Address (R)
    BDAM = 9, // Data Access breakpoint mask (R/W)
    BPCM = 11, // Execute breakpoint mask (R/W)
    SR = 12, // System status register (R/W)
    CAUSE = 13, // (R) Describes the most recently recognised exception
    EPC = 14, // Return Address from Trap (R)
    PRID = 15, // Processor ID (R)
    _,
};

pub const generic_rd = struct {
    rd: cpu.RegisterName,
};

fn decode_generic_rd(op_u32: u32) generic_rd {
    const op: OpCodeHelper = @bitCast(op_u32);
    return .{ .rd = op.b0_15.encoding_a.rd };
}

pub const generic_rs = struct {
    rs: cpu.RegisterName,
};

fn decode_generic_rs(op_u32: u32) generic_rs {
    const op: OpCodeHelper = @bitCast(op_u32);
    return .{ .rs = op.rs };
}

pub const generic_rs_rt = struct {
    rs: cpu.RegisterName,
    rt: cpu.RegisterName,
};

fn decode_generic_rs_rt(op_u32: u32) generic_rs_rt {
    const op: OpCodeHelper = @bitCast(op_u32);
    return .{ .rs = op.rs, .rt = op.rt };
}

pub const generic_rs_rt_imm_u16 = struct {
    rs: cpu.RegisterName,
    rt: cpu.RegisterName,
    imm_u16: u16,
};

fn decode_generic_rs_rt_imm_u16(op_u32: u32) generic_rs_rt_imm_u16 {
    const op: OpCodeHelper = @bitCast(op_u32);
    return .{ .rs = op.rs, .rt = op.rt, .imm_u16 = op.b0_15.encoding_b.imm16 };
}

pub const generic_rs_rt_rd = struct {
    rs: cpu.RegisterName,
    rt: cpu.RegisterName,
    rd: cpu.RegisterName,
};

fn decode_generic_rs_rt_rd(op_u32: u32) generic_rs_rt_rd {
    const op: OpCodeHelper = @bitCast(op_u32);
    return .{ .rs = op.rs, .rt = op.rt, .rd = op.b0_15.encoding_a.rd };
}

pub const generic_rs_rt_imm_i16 = struct {
    rs: cpu.RegisterName,
    rt: cpu.RegisterName,
    imm_i16: i16,
};

fn decode_generic_rs_rt_imm_i16(op_u32: u32) generic_rs_rt_imm_i16 {
    const op: OpCodeHelper = @bitCast(op_u32);
    return .{ .rs = op.rs, .rt = op.rt, .imm_i16 = @bitCast(op.b0_15.encoding_b.imm16) };
}

pub const generic_rt_imm_u16 = struct {
    rt: cpu.RegisterName,
    imm_u16: u16,
};

fn decode_generic_rt_imm_u16(op_u32: u32) generic_rt_imm_u16 {
    const op: OpCodeHelper = @bitCast(op_u32);
    return .{ .rt = op.rt, .imm_u16 = op.b0_15.encoding_b.imm16 };
}

pub const generic_shift_imm = struct {
    rt: cpu.RegisterName,
    rd: cpu.RegisterName,
    shift_imm: u5,
};

fn decode_generic_shift_imm(op_u32: u32) generic_shift_imm {
    const op: OpCodeHelper = @bitCast(op_u32);
    return .{ .rt = op.rt, .rd = op.b0_15.encoding_a.rd, .shift_imm = op.b0_15.encoding_a.imm5 };
}

pub const b_cond_z = struct {
    rs: cpu.RegisterName,
    test_greater: bool,
    link: bool,
    rel_offset: i18,
};

fn decode_b_cond_z(op_u32: u32) b_cond_z {
    const Helper = packed struct {
        imm16: u16,
        test_greater: u1,
        _unused: u3,
        link: u1,
        rs: cpu.RegisterName,
        primary: PrimaryOpCode,
    };

    const op: Helper = @bitCast(op_u32);
    return .{ .rs = op.rs, .test_greater = op.test_greater == 1, .link = op.link == 1 and op._unused == 0, .rel_offset = @bitCast(@as(u18, op.imm16) << 2) };
}

pub const generic_j = struct {
    offset: u28,
};

fn decode_generic_j(op_u32: u32) generic_j {
    return .{ .offset = @as(u28, @as(u26, @truncate(op_u32))) << 2 };
}

pub const j = generic_j;
pub const jal = generic_j;

pub const generic_branch = struct {
    rs: cpu.RegisterName,
    rt: cpu.RegisterName,
    rel_offset: i18,
};

fn decode_generic_branch(op_u32: u32) generic_branch {
    const op: OpCodeHelper = @bitCast(op_u32);
    return .{ .rs = op.rs, .rt = op.rt, .rel_offset = @bitCast(@as(u18, op.b0_15.encoding_b.imm16) << 2) };
}

pub const generic_branch_2 = struct {
    rs: cpu.RegisterName,
    rel_offset: i18,
};

fn decode_generic_branch_2(op_u32: u32) generic_branch_2 {
    const op: OpCodeHelper = @bitCast(op_u32);
    return .{ .rs = op.rs, .rel_offset = @bitCast(@as(u18, op.b0_15.encoding_b.imm16) << 2) };
}

pub const beq = generic_branch;
pub const bne = generic_branch;
pub const blez = generic_branch_2;
pub const bgtz = generic_branch_2;

pub const sll = generic_shift_imm;
pub const srl = generic_shift_imm;
pub const sra = generic_shift_imm;
pub const sllv = generic_rs_rt_rd;
pub const srlv = generic_rs_rt_rd;
pub const srav = generic_rs_rt_rd;

pub const jr = struct {
    rs: cpu.RegisterName,
};

pub const jalr = struct {
    rs: cpu.RegisterName,
    rd: cpu.RegisterName,
};

pub const generic_cop_mov = struct {
    cop_index: u2,
    cpu_rs: cpu.RegisterName, // FIXME
    target: Cop0RegisterName, // FIXME
};

pub const mfc = generic_cop_mov;
pub const cfc = generic_cop_mov;
pub const mtc = generic_cop_mov;
pub const ctc = generic_cop_mov;

pub const generic_cop_bc = struct {
    cop_index: u2,
    condition: bool,
    imm_u16: u16,
};

pub const bcn = generic_cop_bc;

//   31..26 |25..21|20..16|15..11|10..6 |  5..0  |
//    6bit  | 5bit | 5bit | 5bit | 5bit |  6bit  |
//   -------+------+------+------+------+--------+------------
//   1100nn | rs   | rt   | <--immediate16bit--> | LWCn rt_dat,[rs+imm]
//   1110nn | rs   | rt   | <--immediate16bit--> | SWCn rt_dat,[rs+imm]
const RawCopLoadStoreInstruction = packed struct {
    imm_i16: i16,
    rt_cop: u5,
    rs: u5,
    cop_index: u2,
    b28_31: u4,
};

pub const generic_cop_load_store = struct {
    cop_index: u2,
    rt_cop: u5,
    rs: cpu.RegisterName,
    imm_i16: i16,
};

fn decode_generic_cop_load_store(op_u32: u32) generic_cop_load_store {
    const op: RawCopLoadStoreInstruction = @bitCast(op_u32);
    return .{ .cop_index = op.cop_index, .rt_cop = op.rt_cop, .rs = @enumFromInt(op.rs), .imm_i16 = op.imm_i16 };
}

pub const mfhi = generic_rd;
pub const mthi = generic_rs;
pub const mflo = generic_rd;
pub const mtlo = generic_rs;
pub const mult = generic_rs_rt;
pub const multu = generic_rs_rt;
pub const div = generic_rs_rt;
pub const divu = generic_rs_rt;
pub const add = generic_rs_rt_rd;
pub const addu = generic_rs_rt_rd;
pub const sub = generic_rs_rt_rd;
pub const subu = generic_rs_rt_rd;
pub const and_ = generic_rs_rt_rd;
pub const or_ = generic_rs_rt_rd;
pub const xor = generic_rs_rt_rd;
pub const nor = generic_rs_rt_rd;
pub const slt = generic_rs_rt_rd;
pub const sltu = generic_rs_rt_rd;
pub const addi = generic_rs_rt_imm_i16;
pub const addiu = generic_rs_rt_imm_i16;
pub const slti = generic_rs_rt_imm_i16;
pub const sltiu = generic_rs_rt_imm_i16;
pub const andi = generic_rs_rt_imm_u16;
pub const ori = generic_rs_rt_imm_u16;
pub const xori = generic_rs_rt_imm_u16;
pub const lui = generic_rt_imm_u16;
pub const lb = generic_rs_rt_imm_i16;
pub const lh = generic_rs_rt_imm_i16;
pub const lwl = generic_rs_rt_imm_i16;
pub const lw = generic_rs_rt_imm_i16;
pub const lbu = generic_rs_rt_imm_i16;
pub const lhu = generic_rs_rt_imm_i16;
pub const lwr = generic_rs_rt_imm_i16;
pub const sb = generic_rs_rt_imm_i16;
pub const sh = generic_rs_rt_imm_i16;
pub const swl = generic_rs_rt_imm_i16;
pub const sw = generic_rs_rt_imm_i16;
pub const swr = generic_rs_rt_imm_i16;
pub const lwc = generic_cop_load_store;
pub const swc = generic_cop_load_store;
