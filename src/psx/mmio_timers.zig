const std = @import("std");

const PSXState = @import("state.zig").PSXState;
const mmio = @import("mmio.zig");
const mmio_cdrom = @import("cdrom/mmio.zig");

pub fn load_mmio_generic(comptime T: type, psx: *PSXState, offset: u29) T {
    std.debug.assert(offset < MMIO.OffsetEnd);
    std.debug.assert(offset >= MMIO.Offset);

    const timer_offset: TimerOffsetHelper = @bitCast(offset);

    if (offset - MMIO.Offset < @offsetOf(MMIO_Timers, "_unused") and timer_offset.channel_index != .Invalid) {
        // const timer = get_timer(psx, timer_offset.channel_index);

        switch (timer_offset.channel_register) {
            .Value, .Mode, .Target => {
                std.debug.assert(T != u8);

                const type_slice = mmio.get_mutable_mmio_slice(T, psx, offset);

                return std.mem.readInt(T, type_slice, .little);
            },
            .Invalid => unreachable,
        }
    } else {
        unreachable;
    }
}

pub fn store_mmio_generic(comptime T: type, psx: *PSXState, offset: u29, value: T) void {
    std.debug.assert(offset >= MMIO.Offset);
    std.debug.assert(offset < MMIO.OffsetEnd);

    const timer_offset: TimerOffsetHelper = @bitCast(offset);

    if (offset - MMIO.Offset < @offsetOf(MMIO_Timers, "_unused") and timer_offset.channel_index != .Invalid) {
        // const timer = get_timer(psx, timer_offset.channel_index);

        switch (timer_offset.channel_register) {
            .Value, .Mode, .Target => {
                std.debug.assert(T != u8);

                const type_slice = mmio.get_mutable_mmio_slice(T, psx, offset);

                // In case of u32 writes, just keep the full value in.
                std.mem.writeInt(T, type_slice, value, .little);
            },
            .Invalid => unreachable,
        }
    } else {
        unreachable;
    }
}

const TimerOffsetHelper = packed struct {
    b0_1: u2,
    channel_register: TimerRegister,
    channel_index: TimerIndex,
    b5_28: u23,
};

const TimerRegister = enum(u2) {
    Value,
    Mode,
    Target,
    Invalid,
};

const TimerIndex = enum(u2) {
    Timer0,
    Timer1,
    Timer2,
    Invalid,
};

fn get_timer(psx: *PSXState, index: TimerIndex) *MMIO_Timers.Timer {
    return switch (index) {
        .Timer0 => &psx.mmio.timers.timer0,
        .Timer1 => &psx.mmio.timers.timer1,
        .Timer2 => &psx.mmio.timers.timer2,
        .Invalid => unreachable,
    };
}

pub const MMIO = struct {
    pub const Offset = 0x1f801100;
    pub const OffsetEnd = Offset + SizeBytes;

    pub const Packed = MMIO_Timers;

    const SizeBytes = mmio_cdrom.MMIO.Offset - Offset;

    comptime {
        std.debug.assert(@sizeOf(Packed) == SizeBytes);
    }
};

pub const MMIO_Timers = packed struct {
    timer0: Timer = .{},
    timer1: Timer = .{},
    timer2: Timer = .{},
    _unused: u13952 = undefined,

    //1F801100h+N*10h - Timer 0..2 Current Counter Value (R/W)
    //
    //  0-15  Current Counter value (incrementing)
    //  16-31 Garbage
    //
    //This register is automatically incrementing. It is write-able (allowing to set it to any value). It gets forcefully reset to 0000h on any write to the Counter Mode register, and on counter overflow (either when exceeding FFFFh, or when exceeding the selected target value).
    //
    //1F801104h+N*10h - Timer 0..2 Counter Mode (R/W)
    //
    //  0     Synchronization Enable (0=Free Run, 1=Synchronize via Bit1-2)
    //  1-2   Synchronization Mode   (0-3, see lists below)
    //         Synchronization Modes for Counter 0:
    //           0 = Pause counter during Hblank(s)
    //           1 = Reset counter to 0000h at Hblank(s)
    //           2 = Reset counter to 0000h at Hblank(s) and pause outside of Hblank
    //           3 = Pause until Hblank occurs once, then switch to Free Run
    //         Synchronization Modes for Counter 1:
    //           Same as above, but using Vblank instead of Hblank
    //         Synchronization Modes for Counter 2:
    //           0 or 3 = Stop counter at current value (forever, no h/v-blank start)
    //           1 or 2 = Free Run (same as when Synchronization Disabled)
    //  3     Reset counter to 0000h  (0=After Counter=FFFFh, 1=After Counter=Target)
    //  4     IRQ when Counter=Target (0=Disable, 1=Enable)
    //  5     IRQ when Counter=FFFFh  (0=Disable, 1=Enable)
    //  6     IRQ Once/Repeat Mode    (0=One-shot, 1=Repeatedly)
    //  7     IRQ Pulse/Toggle Mode   (0=Short Bit10=0 Pulse, 1=Toggle Bit10 on/off)
    //  8-9   Clock Source (0-3, see list below)
    //         Counter 0:  0 or 2 = System Clock,  1 or 3 = Dotclock
    //         Counter 1:  0 or 2 = System Clock,  1 or 3 = Hblank
    //         Counter 2:  0 or 1 = System Clock,  2 or 3 = System Clock/8
    //  10    Interrupt Request       (0=Yes, 1=No) (Set after Writing)    (W=1) (R)
    //  11    Reached Target Value    (0=No, 1=Yes) (Reset after Reading)        (R)
    //  12    Reached FFFFh Value     (0=No, 1=Yes) (Reset after Reading)        (R)
    //  13-15 Unknown (seems to be always zero)
    //  16-31 Garbage (next opcode)
    //
    //In one-shot mode, the IRQ is pulsed/toggled only once (one-shot mode doesn't stop the counter, it just suppresses any further IRQs until a new write to the Mode register occurs; if both IRQ conditions are enabled in Bit4-5, then one-shot mode triggers only one of those conditions; whichever occurs first).
    //Normally, Pulse mode should be used (Bit10 is permanently set, except for a few clock cycles when an IRQ occurs). In Toggle mode, Bit10 is set after writing to the Mode register, and becomes inverted on each IRQ (in one-shot mode, it remains zero after the IRQ) (in repeat mode it inverts Bit10 on each IRQ, so IRQ4/5/6 are triggered only each 2nd time, ie. when Bit10 changes from 1 to 0).
    //
    //1F801108h+N*10h - Timer 0..2 Counter Target Value (R/W)
    //
    //  0-15  Counter Target value
    //  16-31 Garbage
    //
    //When the Target flag is set (Bit3 of the Control register), the counter increments up to (including) the selected target value, and does then restart at 0000h.

    const Timer = packed struct {
        counter: u16 = 0, // FIXME
        _garbage1: u16 = undefined,
        mode: u16 = 0, // FIXME
        _garbage0: u16 = undefined,
        target: u16 = 0, // FIXME
        _garbage2: u16 = undefined,
        _unknown: u32 = 0, // FIXME
    };
};
