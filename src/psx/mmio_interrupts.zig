const std = @import("std");

const PSXState = @import("state.zig").PSXState;
const mmio_dma = @import("dma/mmio.zig");

const config = @import("config.zig");
const cpu_execution = @import("cpu/execution.zig");

pub fn load_mmio_generic(comptime T: type, psx: *PSXState, offset: u29) T {
    std.debug.assert(offset >= MMIO.Offset);
    std.debug.assert(offset < MMIO.OffsetEnd);

    std.debug.assert(T != u8);

    switch (offset) {
        MMIO.Status_Offset => {
            return psx.mmio.irq.status.raw; // Implicit upcast
        },
        MMIO.Mask_Offset => {
            return psx.mmio.irq.mask.raw; // Implicit upcast
        },
        else => @panic("Invalid IRQ MMIO load offset"),
    }
}

pub fn store_mmio_generic(comptime T: type, psx: *PSXState, offset: u29, value: T) void {
    std.debug.assert(offset >= MMIO.Offset);
    std.debug.assert(offset < MMIO.OffsetEnd);

    std.debug.assert(T != u8);

    switch (offset) {
        MMIO.Status_Offset => {
            // Acknowledge IRQ
            psx.mmio.irq.status.raw &= @truncate(value);

            cpu_execution.update_hardware_interrupt_line(psx);
        },
        MMIO.Mask_Offset => {
            psx.mmio.irq.mask.raw = @truncate(value);

            cpu_execution.update_hardware_interrupt_line(psx);
        },
        else => @panic("Invalid IRQ MMIO store offset"),
    }
}

pub const MMIO = struct {
    pub const Offset = 0x1f801070;
    pub const OffsetEnd = Offset + SizeBytes;

    const Status_Offset = 0x1f801070;
    const Mask_Offset = 0x1f801074;

    pub const Packed = MMIO_IRQ;

    const SizeBytes = mmio_dma.MMIO.Offset - Offset;

    comptime {
        std.debug.assert(@sizeOf(Packed) == SizeBytes);
    }
};

const MMIO_IRQ = packed struct {
    // 0x1f801070 I_STAT - Interrupt status register (R=Status, W=Acknowledge)
    // Status: Read I_STAT (0=No IRQ, 1=IRQ)
    // Acknowledge: Write I_STAT (0=Clear Bit, 1=No change)
    status: InterruptBits = undefined,
    status_zero_b11_15: u5 = 0,
    _unused_control: u16 = undefined,

    // 0x1f801074 I_MASK - Interrupt mask register (R/W)
    // Mask: Read/Write I_MASK (0=Disabled, 1=Enabled)
    mask: InterruptBits = undefined,
    mask_zero_b11_15: u5 = 0,
    _unused_mask: u16 = undefined,

    _unused: u64 = undefined,

    pub const InterruptBits = packed union {
        raw: u11,
        typed: packed struct {
            irq0_vblank: u1, // 0     IRQ0 VBLANK (PAL=50Hz, NTSC=60Hz)
            irq1_gpu: u1, //    1     IRQ1 GPU   Can be requested via GP0(1Fh) command (rarely used)
            irq2_cdrom: u1, //  2     IRQ2 CDROM
            irq3_dma: u1, //    3     IRQ3 DMA
            irq4_tmr0: u1, //   4     IRQ4 TMR0  Timer 0 aka Root Counter 0 (Sysclk or Dotclk)
            irq5_tmr1: u1, //   5     IRQ5 TMR1  Timer 1 aka Root Counter 1 (Sysclk or H-blank)
            irq6_tmr2: u1, //   6     IRQ6 TMR2  Timer 2 aka Root Counter 2 (Sysclk or Sysclk/8)
            irq7_controller_memory_card: u1, //   7     IRQ7 Controller and Memory Card - Byte Received Interrupt
            irq8_sio: u1, //    8     IRQ8 SIO
            irq9_spu: u1, //    9     IRQ9 SPU
            irq10_controller_lightpen: u1, //   10    IRQ10 Controller - Lightpen Interrupt (reportedly also PIO...?)
        },
    };
    //
    // Secondary IRQ10 Controller (Port 1F802030h)
    // EXP2 DTL-H2000 I/O Ports
    //
    // Interrupt Request / Execution
    // The interrupt request bits in I_STAT are edge-triggered, ie. the get set ONLY if the corresponding interrupt source changes from "false to true".
    // If one or more interrupts are requested and enabled, ie. if "(I_STAT AND I_MASK)=nonzero", then cop0r13.bit10 gets set, and when cop0r12.bit10 and cop0r12.bit0 are set, too, then the interrupt gets executed.
    //
    // Interrupt Acknowledge
    // To acknowledge an interrupt, write a "0" to the corresponding bit in I_STAT. Most interrupts (except IRQ0,4,5,6) must be additionally acknowledged at the I/O port that has caused them (eg. JOY_CTRL.bit4).
    // Observe that the I_STAT bits are edge-triggered (they get set only on High-to-Low, or False-to-True edges). The correct acknowledge order is:
    //
    //   First, acknowledge I_STAT                (eg. I_STAT.bit7=0)
    //   Then, acknowledge corresponding I/O port (eg. JOY_CTRL.bit4=1)
    //
    // When doing it vice-versa, the hardware may miss further IRQs (eg. when first setting JOY_CTRL.4=1, then a new IRQ may occur in JOY_STAT.4 within a single clock cycle, thereafter, setting I_STAT.7=0 would successfully reset I_STAT.7, but, since JOY_STAT.4 is already set, there'll be no further edge, so I_STAT.7 won't be ever set in future).
    //
    // COP0 Interrupt Handling
    // Relevant COP0 registers are cop0r13 (CAUSE, reason flags), and cop0r12 (SR, control flags), and cop0r14 (EPC, return address), and, cop0cmd=10h (aka RFE opcode) is used to prepare the return from interrupts. For more info, see
    // COP0 - Exception Handling
    //
    // PSX specific COP0 Notes
    // COP0 has six hardware interrupt bits, of which, the PSX uses only cop0r13.bit10 (the other ones, cop0r13.bit11-15 are always zero). cop0r13.bit10 is NOT a latch, ie. it gets automatically cleared as soon as "(I_STAT AND I_MASK)=zero", so there's no need to do an acknowledge at the cop0 side. COP0 additionally has two software interrupt bits, cop0r13.bit8-9, which do exist in the PSX, too, these bits are read/write-able latches which can be set/cleared manually to request/acknowledge exceptions by software.
    //
    // Halt Function (Wait for Interrupt)
    // The PSX doesn't have a HALT opcode, so, even if the program is merely waiting for an interrupt to occur, the CPU is always running at full speed, which is resulting in high power consumption, and, in case of emulators, high CPU emulation load. To save energy, and to make emulation smoother on slower computers, I've added a Halt function for use in emulators:
    // EXP2 Nocash Emulation Expansion
};
