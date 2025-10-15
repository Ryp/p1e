pub const CPUState = struct {
    regs: Registers = .{},
    branch: bool = false,
    delay_slot: bool = false,

    pub fn write(self: @This(), writer: anytype) !void {
        try self.regs.write(writer);

        try writer.writeByte(if (self.branch) 1 else 0);
        try writer.writeByte(if (self.delay_slot) 1 else 0);
    }

    pub fn read(self: *@This(), reader: anytype) !void {
        try self.regs.read(reader);

        self.branch = try reader.readByte() != 0;
        self.delay_slot = try reader.readByte() != 0;
    }
};

pub const Registers = struct {
    pc: u32 = 0xbfc00000, // Program Counter
    next_pc: u32 = 0xbfc00000 + 4, // Pipelined Program Counter
    current_instruction_pc: u32 = undefined,
    epc: u32 = undefined, // Exception Program Counter

    r_in: [32]u32 = undefined, // FIXME does it have an initial value?
    r_out: [32]u32 = undefined, // FIXME does it have an initial value?
    hi: u32 = undefined, // FIXME does it have an initial value?
    lo: u32 = undefined, // FIXME does it have an initial value?
    bad_vaddr: u32 = undefined, // FIXME does it have an initial value?
    sr: SystemRegister = undefined, // FIXME does it have an initial value?
    cause: CauseRegister = undefined, // FIXME does it have an initial value?

    pending_load: ?struct {
        register: RegisterName,
        value: u32,
        is_unaligned: bool = false,
    } = null,

    pub fn write(self: @This(), writer: anytype) !void {
        try writer.writeInt(@TypeOf(self.pc), self.pc, .little);
        try writer.writeInt(@TypeOf(self.next_pc), self.next_pc, .little);
        try writer.writeInt(@TypeOf(self.current_instruction_pc), self.current_instruction_pc, .little);
        try writer.writeInt(@TypeOf(self.epc), self.epc, .little);

        for (self.r_in, self.r_out) |r_in, r_out| {
            try writer.writeInt(u32, r_in, .little);
            try writer.writeInt(u32, r_out, .little);
        }

        try writer.writeInt(@TypeOf(self.hi), self.hi, .little);
        try writer.writeInt(@TypeOf(self.lo), self.lo, .little);

        try writer.writeInt(@TypeOf(self.bad_vaddr), self.bad_vaddr, .little);
        try writer.writeStruct(self.sr);
        try writer.writeStruct(self.cause);

        if (self.pending_load) |pending_load| {
            try writer.writeByte(1); // optional
            try writer.writeByte(@intFromEnum(pending_load.register));
            try writer.writeInt(@TypeOf(pending_load.value), pending_load.value, .little);
            try writer.writeByte(if (pending_load.is_unaligned) 1 else 0);
        } else {
            try writer.writeByte(0); // optional
            try writer.writeByte(0); // register
            try writer.writeInt(u32, 0, .little); // value
            try writer.writeByte(0); // is_unaligned
        }
    }

    pub fn read(self: *@This(), reader: anytype) !void {
        self.pc = try reader.readInt(@TypeOf(self.pc), .little);
        self.next_pc = try reader.readInt(@TypeOf(self.next_pc), .little);
        self.current_instruction_pc = try reader.readInt(@TypeOf(self.current_instruction_pc), .little);
        self.epc = try reader.readInt(@TypeOf(self.epc), .little);

        for (&self.r_in, &self.r_out) |*r_in, *r_out| {
            r_in.* = try reader.readInt(u32, .little);
            r_out.* = try reader.readInt(u32, .little);
        }

        self.hi = try reader.readInt(@TypeOf(self.hi), .little);
        self.lo = try reader.readInt(@TypeOf(self.lo), .little);

        self.bad_vaddr = try reader.readInt(@TypeOf(self.bad_vaddr), .little);
        self.sr = try reader.readStruct(@TypeOf(self.sr));
        self.cause = try reader.readStruct(@TypeOf(self.cause));

        const has_pending_load = try reader.readByte() != 0;
        const register: RegisterName = @enumFromInt(try reader.readByte());
        const value = try reader.readInt(u32, .little);
        const is_unaligned = try reader.readByte() != 0;

        self.pending_load = if (has_pending_load)
            .{
                .register = register,
                .value = value,
                .is_unaligned = is_unaligned,
            }
        else
            null;
    }
};

// Register Name Conventional use
pub const RegisterName = enum(u5) {
    zero = 0, // Always zero
    at = 1, // Assembler temporary
    v0 = 2, // Function return values
    v1 = 3,
    a0 = 4, // Function arguments
    a1,
    a2,
    a3,
    t0 = 8, // Temporary registers
    t1,
    t2,
    t3,
    t4,
    t5,
    t6,
    t7,
    s0 = 16, // Saved registers
    s1,
    s2,
    s3,
    s4,
    s5,
    s6,
    s7,
    t8 = 24, // Temporary registers
    t9 = 25,
    k0 = 26, // Kernel reserved registers
    k1 = 27,
    gp = 28, // Global pointer
    sp = 29, // Stack pointer
    fp = 30, // Frame pointer
    ra = 31, // Function return address
};

const SystemRegister = packed struct(u32) {
    interrupt_stack: packed struct(u6) {
        const InterruptStackElement = packed struct(u2) {
            enabled: bool,
            mode: enum(u1) {
                Kernel,
                User,
            },
        };

        // 0     IEc Current Interrupt Enable  (0=Disable, 1=Enable) ;rfe pops IEp here
        // 1     KUc Current Kernel/User Mode  (0=Kernel, 1=User)    ;rfe pops KUp here
        // 2     IEp Previous Interrupt Disable                      ;rfe pops IEo here
        // 3     KUp Previous Kernel/User Mode                       ;rfe pops KUo here
        // 4     IEo Old Interrupt Disable                       ;left unchanged by rfe
        // 5     KUo Old Kernel/User Mode                        ;left unchanged by rfe
        current: InterruptStackElement,
        previous: InterruptStackElement,
        old: InterruptStackElement,
    },
    // 6-7   -   Not used (zero)
    _unused_b6_7: u2,
    // 8-15  Im  8 bit interrupt mask fields. When set the corresponding
    //           interrupts are allowed to cause an exception.
    interrupt_mask: u3, // Im
    interrupt_mask_unused: u5, // Only the first bits are really useful
    // 16    Isc Isolate Cache (0=No, 1=Isolate)
    //             When isolated, all load and store operations are targetted
    //             to the Data cache, and never the main memory.
    //             (Used by PSX Kernel, in combination with Port FFFE0130h)
    isolate_cache: u1, // Isc
    // 17    Swc Swapped cache mode (0=Normal, 1=Swapped)
    //             Instruction cache will act as Data cache and vice versa.
    //             Use only with Isc to access & invalidate Instr. cache entries.
    //             (Not used by PSX Kernel)
    swapped_cache: u1, // Swc
    // 18    PZ  When set cache parity bits are written as 0.
    cache_parity: u1,
    // 19    CM  Shows the result of the last load operation with the D-cache
    //           isolated. It gets set if the cache really contained data
    //           for the addressed memory location.
    cm: u1,
    // 20    PE  Cache parity error (Does not cause exception)
    cache_parity_error: u1,
    // 21    TS  TLB shutdown. Gets set if a programm address simultaneously
    //           matches 2 TLB entries.
    //           (initial value on reset allows to detect extended CPU version?)
    ts: u1,
    // 22    BEV Boot exception vectors in RAM/ROM (0=RAM/KSEG0, 1=ROM/KSEG1)
    bev: u1,
    // 23-24 -   Not used (zero)
    _unused_b23_24: u2,
    // 25    RE  Reverse endianness   (0=Normal endianness, 1=Reverse endianness)
    //             Reverses the byte order in which data is stored in
    //             memory. (lo-hi -> hi-lo)
    //             (Has affect only to User mode, not to Kernal mode) (?)
    //             (The bit doesn't exist in PSX ?)
    reverse_endianness: u1,
    // 26-27 -   Not used (zero)
    // 28    CU0 COP0 Enable (0=Enable only in Kernal Mode, 1=Kernal and User Mode)
    // 29    CU1 COP1 Enable (0=Disable, 1=Enable) (none such in PSX)
    // 30    CU2 COP2 Enable (0=Disable, 1=Enable) (GTE in PSX)
    // 31    CU3 COP3 Enable (0=Disable, 1=Enable) (none such in PSX)
    _unused_b26_31: u6,
};

const CauseRegister = packed struct(u32) {
    // 0-1   -      Not used (zero)
    _unused_b0_1: u2,
    // 2-6   Excode Describes what kind of exception occured:
    cause: ExceptionCause,
    // 7     -      Not used (zero)
    _unused_b7: u1,
    // 8-15  Ip     Interrupt pending field. Bit 8 and 9 are R/W, and
    //              contain the last value written to them. As long
    //              as any of the bits are set they will cause an
    //              interrupt if the corresponding bit is set in IM.
    interrupt_pending: packed struct(u3) {
        software_irq0: bool,
        software_irq1: bool,
        hardware_irq: bool,
    },
    interrupt_pending_unused: u5, // Only the first HW interrupt is wired
    // 16-27 -      Not used (zero)
    _unused_b16_27: u12,
    // 28-29 CE     Opcode Bit26-27 (aka coprocessor number in case of COP opcodes)
    opcode: u2,
    // 30    -      Not used (zero) / Undoc: When BD=1, Branch condition (0=False)
    _unused_b30: u1,
    // 31    BD     Branch Delay (set when last exception points to the branch
    //              instruction instead of the instruction in the branch delay
    //              slot, where the exception occurred)
    branch_delay: u1,
};

pub const ExceptionCause = enum(u5) {
    INT = 0x00, // Interrupt
    MOD = 0x01, // Tlb modification (none such in PSX)
    TLBL = 0x02, // Tlb load         (none such in PSX)
    TLBS = 0x03, // Tlb store        (none such in PSX)
    AdEL = 0x04, // Address error, Data load or Instruction fetch
    // Address error, Data store
    // The address errors occur when attempting to read
    // outside of KUseg in user mode and when the address
    // is misaligned. (See also: BadVaddr register)
    AdES = 0x05,
    IBE = 0x06, // Bus error on Instruction fetch
    DBE = 0x07, // Bus error on Data load/store
    SysCall = 0x08, // Generated unconditionally by syscall instruction
    BP = 0x09, // Breakpoint - break instruction
    RI = 0x0A, // Reserved instruction
    CpU = 0x0B, // Coprocessor unusable
    Ov = 0x0C, // Arithmetic overflow
    _,
};

// cop0r15 - PRID - Processor ID (R)
//
//   0-7   Revision
//   8-15  Implementation
//   16-31 Not used
//
// PRID=00000001h on Playstation with CPU CXD8530BQ/CXD8530CQ
// PRID=00000002h on Playstation with CPU CXD8606CQ
pub const CPU_PRID = 0x00_00_00_02;

pub const ClockTicksPerSeconds = 33_868_800;

comptime {
    const std = @import("std");
    std.debug.assert(ClockTicksPerSeconds == 44100 * 256 * 3);
}
