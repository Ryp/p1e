const std = @import("std");

const PSXState = @import("../state.zig").PSXState;

const mmio = @import("../mmio.zig");
const memory_control2 = @import("../mmio_memory_control2.zig");
const config = @import("../config.zig");

const execution = @import("execution.zig");

pub fn load_mmio_generic(comptime T: type, psx: *PSXState, offset: u29) T {
    std.debug.assert(offset >= MMIO.Offset);
    std.debug.assert(offset < MMIO.OffsetEnd);

    const type_slice = mmio.get_mutable_mmio_slice_generic(T, psx, offset);

    switch (offset) {
        MMIO.Joy_DATA_Offset => {
            std.debug.assert(T == u8); // Games can peak at next values but our FIFO is 1 item deep

            if (psx.ports.joy.rx_fifo) |value| {
                psx.ports.joy.rx_fifo = null;
                return value;
            } else {
                return 0xff;
            }
        },
        MMIO.Joy_STAT_Offset => {
            psx.mmio.ports.joy.stat = .{
                .tx_ready_started = true, // FIXME Rustation always sets them
                .rx_fifo_not_empty = psx.ports.joy.rx_fifo != null,
                .tx_ready_finished = true, // FIXME Rustation always sets them
                .rx_has_parity_error = false, // We're emulating so no reason to have a parity error
                .ack_input_level = .High, // FIXME
                .irq7_requested = false, // FIXME
                .baudrate_timer = 0, // FIXME Rustation doesn't set this
            };

            if (config.enable_ports_debug) {
                std.debug.print("JOY_STAT: {}\n", .{psx.mmio.ports.joy.stat});
            }

            return std.mem.readInt(T, type_slice, .little);
        },
        MMIO.Joy_MODE_Offset => {
            unreachable;
        },
        MMIO.Joy_CTRL_Offset => {
            std.debug.assert(T == u16);

            return std.mem.readInt(T, type_slice, .little);
        },
        else => {
            std.debug.print("FIXME IOPorts load forbidden at offset {x}\n", .{offset});
            @panic("Invalid Ports MMIO load offset");
        },
    }
}

pub fn store_mmio_generic(comptime T: type, psx: *PSXState, offset: u29, value: T) void {
    std.debug.assert(offset >= MMIO.Offset);
    std.debug.assert(offset < MMIO.OffsetEnd);

    const type_slice = mmio.get_mutable_mmio_slice_generic(T, psx, offset);

    switch (offset) {
        MMIO.Joy_DATA_Offset => {
            std.debug.assert(T == u8);

            // FIXME dummy response
            psx.ports.joy.rx_fifo = 0xff;
        },
        MMIO.Joy_STAT_Offset => {
            @panic("Invalid write to Joy_STAT_Offset");
        },
        MMIO.Joy_MODE_Offset => {
            std.mem.writeInt(T, type_slice, value, .little);

            if (config.enable_ports_debug) {
                std.debug.print("IOPorts JOY MODE set: {}\n", .{psx.mmio.ports.joy.mode});
            }

            std.debug.assert(psx.mmio.ports.joy.mode.zero_b6_7 == 0);
            std.debug.assert(psx.mmio.ports.joy.mode.zero_b9_15 == 0);
        },
        MMIO.Joy_CTRL_Offset => {
            std.mem.writeInt(T, type_slice, value, .little);

            if (config.enable_ports_debug) {
                std.debug.print("IOPorts JOY CTRL set: {}\n", .{psx.mmio.ports.joy.ctrl});
            }

            std.debug.assert(psx.mmio.ports.joy.ctrl.zero_b7 == 0);
            std.debug.assert(psx.mmio.ports.joy.ctrl.zero_b14_15 == 0);

            if (psx.mmio.ports.joy.ctrl.ack_irq) {
                psx.mmio.ports.joy.ctrl.ack_irq = false;

                if (config.enable_ports_debug) {
                    std.debug.print("IOPorts ACK IRQ\n", .{});
                }

                psx.mmio.ports.joy.stat.irq7_requested = false;
            }

            if (psx.mmio.ports.joy.ctrl.reset) {
                psx.mmio.ports.joy.ctrl.reset = false;

                if (config.enable_ports_debug) {
                    std.debug.print("IOPorts Reset\n", .{});
                }
                execution.reset_joy(psx);
            }
        },
        MMIO.Joy_BAUD_Offset => {
            std.debug.assert(T == u16);

            std.mem.writeInt(T, type_slice, value, .little);
        },
        else => @panic("Invalid Ports MMIO store offset"),
    }
}

pub const MMIO = struct {
    pub const Offset = 0x1f801040;
    pub const OffsetEnd = Offset + SizeBytes;

    const SizeBytes = memory_control2.MMIO.Offset - Offset;

    comptime {
        std.debug.assert(@sizeOf(Packed) == SizeBytes);
    }

    pub const Joy_DATA_Offset = 0x1f801040;
    pub const Joy_STAT_Offset = 0x1f801044;
    pub const Joy_MODE_Offset = 0x1f801048;
    pub const Joy_CTRL_Offset = 0x1f80104a;

    pub const Joy_BAUD_Offset = 0x1f80104e;

    pub const SIO_DATA_Offset = 0x1f801050;
    pub const SIO_STAT_Offset = 0x1f801054;
    pub const SIO_MODE_Offset = 0x1f801058;
    pub const SIO_CTRL_Offset = 0x1f80105a;
    pub const SIO_MISC_Offset = 0x1f80105c;
    pub const SIO_BAUD_Offset = 0x1f80105e;

    pub const Packed = packed struct(u256) {
        joy: packed struct(u128) {
            data: u32 = undefined, // 1F801040h 1/4  JOY_DATA Joypad/Memory Card Data (R/W)
            stat: packed struct(u32) { // 1F801044h 4    JOY_STAT Joypad/Memory Card Status (R)
                tx_ready_started: bool, //  0     TX Ready Flag 1   (1=Ready/Started)
                rx_fifo_not_empty: bool, //  1     RX FIFO Not Empty (0=Empty, 1=Not Empty)
                tx_ready_finished: bool, //  2     TX Ready Flag 2   (1=Ready/Finished)
                rx_has_parity_error: bool, //  3     RX Parity Error   (0=No, 1=Error; Wrong Parity, when enabled)  (sticky)
                //  4     Unknown (zero)    (unlike SIO, this isn't RX FIFO Overrun flag)
                //  5     Unknown (zero)    (for SIO this would be RX Bad Stop Bit)
                //  6     Unknown (zero)    (for SIO this would be RX Input Level AFTER Stop bit)
                zero_b4_6: u3 = 0,
                ack_input_level: enum(u1) { //  7     /ACK Input Level  (0=High, 1=Low)
                    High = 0,
                    Low = 1,
                },
                zero_b8: u1 = 0, //  8     Unknown (zero)    (for SIO this would be CTS Input Level)
                irq7_requested: bool, //  9     Interrupt Request (0=None, 1=IRQ7) (See JOY_CTRL.Bit4,10-12)   (sticky)
                zero_b10: u1 = 0, //  10    Unknown (always zero)
                baudrate_timer: u21, //  11-31 Baudrate Timer    (21bit timer, decrementing at 33MHz)
            } = undefined,
            mode: packed struct(u16) { // 1F801048h 2    JOY_MODE Joypad/Memory Card Mode (R/W)
                // 1F801048h JOY_MODE (R/W) (usually 000Dh, ie. 8bit, no parity, MUL1)
                baudrate_reload_factor: enum(u2) { //  0-1   Baudrate Reload Factor (1=MUL1, 2=MUL16, 3=MUL64) (or 0=MUL1, too)
                    x1_also = 0,
                    x1 = 1,
                    x16 = 2,
                    x64 = 3,
                },
                character_length: enum(u2) { //  2-3   Character Length       (0=5bits, 1=6bits, 2=7bits, 3=8bits)
                    _5bits = 0,
                    _6bits = 1,
                    _7bits = 2,
                    _8bits = 3,
                },
                enable_parity: bool, //  4     Parity Enable   (0=No, 1=Enable)
                parity_type: enum(u1) { //  5     Parity Type  (0=Even, 1=Odd) (seems to be vice-versa...?)
                    Even = 0,
                    Odd = 1,
                },
                zero_b6_7: u2, //  6-7   Unknown (always zero)
                b8: enum(u1) { //  8     CLK Output Polarity    (0=Normal:High=Idle, 1=Inverse:Low=Idle)
                    NormalHighIdle = 0,
                    InverseLowIdle = 1,
                },
                zero_b9_15: u7, //  9-15  Unknown (always zero)
            } = undefined,
            ctrl: packed struct(u16) { // 1F80104Ah 2    JOY_CTRL Joypad/Memory Card Control (R/W)
                // 1F80104Ah JOY_CTRL (R/W) (usually 1003h,3003h,0000h)
                tx_enable: bool, //  0     TX Enable (TXEN)  (0=Disable, 1=Enable)
                output_mode: enum(u1) { //  1     /JOYn Output      (0=High, 1=Low/Select) (/JOYn as defined in Bit13)
                    High = 0,
                    Low_Select = 1,
                },
                rx_enable: bool, //  2     RX Enable (RXEN)  (0=Normal, when /JOYn=Low, 1=Force Enable Once)
                unknown_b3: u1, //  3     Unknown? (read/write-able) (for SIO, this would be TX Output Level)
                ack_irq: bool, //  4     Acknowledge       (0=No change, 1=Reset JOY_STAT.Bits 3,9)          (W)
                unknown_b5: u1, //  5     Unknown? (read/write-able) (for SIO, this would be RTS Output Level)
                reset: bool, //  6     Reset             (0=No change, 1=Reset most JOY_registers to zero) (W)
                zero_b7: u1, //  7     Not used             (always zero) (unlike SIO, no matter of FACTOR)
                rx_irq_mode: enum(u2) { //  8-9   RX Interrupt Mode    (0..3 = IRQ when RX FIFO contains 1,2,4,8 bytes)
                    _1byte = 0,
                    _2bytes = 1,
                    _4bytes = 2,
                    _8bytes = 3,
                },
                tx_irq_enable: bool, //  10    TX Interrupt Enable  (0=Disable, 1=Enable) ;when JOY_STAT.0-or-2 ;Ready
                rx_irq_enable: bool, //  11    RX Interrupt Enable  (0=Disable, 1=Enable) ;when N bytes in RX FIFO
                ack_irq_enable: bool, //  12    ACK Interrupt Enable (0=Disable, 1=Enable) ;when JOY_STAT.7  ;/ACK=LOW
                selected_slot: enum(u1) { //  13    Desired Slot Number  (0=/JOY1, 1=/JOY2) (set to LOW when Bit1=1)
                    Joy1 = 0,
                    Joy2 = 1,
                },
                zero_b14_15: u2, //  14-15 Not used             (always zero)
            } = undefined,
            unused: u16 = undefined,
            baud: u16 = undefined, // 1F80104Eh 2    JOY_BAUD Joypad/Memory Card Baudrate (R/W)
        } = .{},
        sio: packed struct(u128) {
            data: u32 = undefined, // 1F801050h 1/4  SIO_DATA Serial Port Data (R/W)
            stat: u32 = undefined, // 1F801054h 4    SIO_STAT Serial Port Status (R)
            mode: u16 = undefined, // 1F801058h 2    SIO_MODE Serial Port Mode (R/W)
            ctrl: u16 = undefined, // 1F80105Ah 2    SIO_CTRL Serial Port Control (R/W)
            misc: u16 = undefined, // 1F80105Ch 2    SIO_MISC Serial Port Internal Register (R/W)
            baud: u16 = undefined, // 1F80105Eh 2    SIO_BAUD Serial Port Baudrate (R/W)
        } = .{},
    };
};
