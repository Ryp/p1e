const std = @import("std");

const mmio = @import("mmio.zig");
const irq = @import("mmio_interrupts.zig");

const PSXState = @import("state.zig").PSXState;

pub fn load_mmio_u32(psx: *PSXState, offset: u29) u32 {
    std.debug.assert(offset >= MMIO.Offset);
    std.debug.assert(offset < MMIO.OffsetEnd);

    const type_slice = mmio.get_mutable_mmio_slice_generic(u32, psx, offset);

    switch (offset) {
        MMIO.Expansion1BaseAddress_Offset,
        MMIO.Expansion2BaseAddress_Offset,
        MMIO.Expansion1DelaySize_Offset,
        MMIO.Expansion3DelaySize_Offset,
        MMIO.BiosDelaySize_Offset,
        MMIO.SpuDelaySize_Offset,
        MMIO.CDROMDelaySize_Offset,
        MMIO.Expansion2DelaySize_Offset,
        MMIO.ComDelay_Offset => {
            return std.mem.readInt(u32, type_slice, .little);
        },
        else => {
            std.debug.print("Unsupported MC1 MMIO load at offset {x}", .{offset});
            @panic("Invalid address");
        },
    }
}

pub fn store_mmio_u32(psx: *PSXState, offset: u29, value: u32) void {
    std.debug.assert(offset >= MMIO.Offset);
    std.debug.assert(offset < MMIO.OffsetEnd);

    const type_slice = mmio.get_mutable_mmio_slice_generic(u32, psx, offset);

    switch (offset) {
        MMIO.Expansion1BaseAddress_Offset => {
            std.debug.assert(value == 0x1f000000);
            std.mem.writeInt(u32, type_slice, value, .little);
        },
        MMIO.Expansion2BaseAddress_Offset => {
            std.debug.assert(value == 0x1f802000);
            std.mem.writeInt(u32, type_slice, value, .little);
        },
        MMIO.Expansion1DelaySize_Offset,
        MMIO.Expansion3DelaySize_Offset,
        MMIO.BiosDelaySize_Offset,
        MMIO.SpuDelaySize_Offset,
        MMIO.CDROMDelaySize_Offset,
        MMIO.Expansion2DelaySize_Offset,
        MMIO.ComDelay_Offset => {
            const delay_size: MMIO.Packed.DelaySize = @bitCast(value);
            std.debug.assert(delay_size.zero_b21_23 == 0);
            std.debug.assert(delay_size.zero_b28 == 0);
            std.debug.assert(delay_size.zero_b30 == 0);
            std.debug.assert(delay_size.unknown_b31 == 0 or offset == MMIO.Expansion1DelaySize_Offset);

            std.mem.writeInt(u32, type_slice, value, .little);
        },
        else => {
            std.debug.print("Unsupported MC1 MMIO write at offset {x}", .{offset});
            @panic("Invalid address");
        },
    }
}

pub const MMIO = struct {
    pub const Offset = 0x1f801000;
    pub const OffsetEnd = Offset + SizeBytes;

    const SizeBytes = mmio.IOPorts_MMIO.Offset - Offset;

    comptime {
        std.debug.assert(@sizeOf(Packed) == SizeBytes);
    }

    const Expansion1BaseAddress_Offset = 0x1f801000;
    const Expansion2BaseAddress_Offset = 0x1f801004;
    const Expansion1DelaySize_Offset = 0x1f801008;
    const Expansion3DelaySize_Offset = 0x1f80100c;
    const BiosDelaySize_Offset = 0x1f801010;
    const SpuDelaySize_Offset = 0x1f801014;
    const CDROMDelaySize_Offset = 0x1f801018;
    const Expansion2DelaySize_Offset = 0x1f80101c;
    const ComDelay_Offset = 0x1f801020;

    pub const Packed = packed struct {
        expansion1_base_address: u32 = undefined,
        expansion2_base_address: u32 = undefined,
        expansion1_delay_size: DelaySize = undefined,
        expansion3_delay_size: DelaySize = undefined,
        bios_delay_size: DelaySize = undefined,
        spu_delay_size: DelaySize = undefined,
        cdrom_delay_size: DelaySize = undefined,
        exp2_delay_size: DelaySize = undefined,
        com_delay: u32 = undefined,

        _unused: u224 = undefined,

        const DelaySize = packed struct(u32) {
            unknown_b0_3: u4, // 0-3   Unknown (R/W)
            access_time: u4, // 4-7   Access Time        (00h..0Fh=00h..0Fh Cycles)
            use_com0_time: bool, // 8     Use COM0 Time      (0=No, 1=Yes, add to Access Time)
            use_com1_time: bool, // 9     Use COM1 Time      (0=No, 1=Probably Yes, but has no effect?)
            use_com2_time: bool, // 10    Use COM2 Time      (0=No, 1=Yes, add to Access Time)
            use_com3_time: bool, // 11    Use COM3 Time      (0=No, 1=Yes, clip to MIN=(COM3+6) or so?)
            data_bus_width: enum(u1) { // 12    Data Bus-width     (0=8bit, 1=16bit)
                _8bits = 0,
                _16bits = 1,
            },
            unknown_b13_15: u3, // 13-15 Unknown (R/W)
            memory_window_size: u5, // 16-20 Memory Window Size (1 SHL N bytes) (0..1Fh = 1 byte ... 2 gigabytes)
            zero_b21_23: u3, // 21-23 Unknown (always zero)
            unknown_b24_27: u4, // 24-27 Unknown (R/W) ;must be non-zero for SPU-RAM reads
            zero_b28: u1, // 28    Unknown (always zero)
            unknown_b29: u1, // 29    Unknown (R/W)
            zero_b30: u1, // 30    Unknown (always zero)
            unknown_b31: u1, // 31    Unknown (R/W) (Port 1F801008h only; always zero for other ports)
        };
    };
};
