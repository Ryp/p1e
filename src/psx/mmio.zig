const std = @import("std");

const psx_state = @import("state.zig");
const PSXState = psx_state.PSXState;

const memory_control1 = @import("mmio_memory_control1.zig");
const memory_control2 = @import("mmio_memory_control2.zig");
const irq = @import("mmio_interrupts.zig");
const dma = @import("dma/mmio.zig");
const timers = @import("mmio_timers.zig");
const cdrom = @import("cdrom/mmio.zig");
const gpu = @import("gpu/mmio.zig");
const spu = @import("spu/mmio.zig");

const config = @import("config.zig");

pub fn load_u8(psx: *PSXState, address: u32) u8 {
    return load_generic(u8, psx, @bitCast(address));
}

pub fn load_u16(psx: *PSXState, address: u32) u16 {
    return load_generic(u16, psx, @bitCast(address));
}

pub fn load_u32(psx: *PSXState, address: u32) u32 {
    return load_generic(u32, psx, @bitCast(address));
}

pub fn store_u8(psx: *PSXState, address: u32, value: u8) void {
    store_generic(u8, psx, @bitCast(address), value);
}

pub fn store_u16(psx: *PSXState, address: u32, value: u16) void {
    store_generic(u16, psx, @bitCast(address), value);
}

pub fn store_u32(psx: *PSXState, address: u32, value: u32) void {
    store_generic(u32, psx, @bitCast(address), value);
}

// FIXME check if this is legal
pub fn get_mutable_mmio_slice_generic(comptime T: type, psx: *PSXState, offset: u29) *[@typeInfo(T).int.bits / 8]u8 {
    const type_bytes = @typeInfo(T).int.bits / 8;

    const local_offset = offset - MMIO_Offset;
    const mmio_bytes = std.mem.asBytes(&psx.mmio);
    const type_slice = mmio_bytes[local_offset..][0..type_bytes];

    return type_slice;
}

pub const PSXAddress = packed struct {
    offset: u29,
    mapping: enum(u3) {
        Useg = 0b000,
        Kseg0 = 0b100,
        Kseg1 = 0b101,
        Kseg2 = 0b111,
    },
};

// FIXME does cache isolation has any impact here?
fn load_generic(comptime T: type, psx: *PSXState, address: PSXAddress) T {
    const type_info = @typeInfo(T);
    const type_bits = type_info.int.bits;
    const type_bytes = type_bits / 8;

    std.debug.assert(type_info.int.signedness == .unsigned);
    std.debug.assert(type_bits % 8 == 0);

    if (config.enable_debug_print) {
        std.debug.print("load addr: 0x{x:0>8}\n", .{@as(u32, @bitCast(address))});
    }

    std.debug.assert(address.offset % type_bytes == 0);

    switch (address.mapping) {
        .Useg, .Kseg0, .Kseg1 => {
            switch (address.offset) {
                RAM_Offset...RAM_OffsetEnd - 1 => |offset| {
                    const local_offset = offset - RAM_Offset;
                    const type_slice = psx.ram[local_offset..][0..type_bytes];
                    return std.mem.readInt(T, type_slice, .little);
                },
                MMIO_Offset...MMIO_OffsetEnd - 1 => |offset| {
                    switch (offset) {
                        memory_control1.MMIO.Offset...memory_control1.MMIO.OffsetEnd - 1 => {
                            switch (T) {
                                u32 => return memory_control1.load_mmio_u32(psx, offset),
                                else => @panic("Invalid MC1 MMIO load type"),
                            }
                        },
                        IOPorts_MMIO.Offset...IOPorts_MMIO.OffsetEnd - 1 => {
                            std.debug.print("FIXME IOPorts load ignored at offset {x}\n", .{offset});

                            if (offset == IOPorts_MMIO.Joy_RX_TX_Offset) {
                                return 0; // FIXME
                            } else if (offset == IOPorts_MMIO.Joy_Ctrl_Offset) {
                                return 0; // FIXME
                            }

                            @panic("Invalid address");
                        },
                        memory_control2.MMIO.Offset...memory_control2.MMIO.OffsetEnd - 1 => {
                            switch (T) {
                                u16, u32 => return memory_control2.load_mmio_generic(T, psx, offset),
                                else => @panic("Invalid MC2 MMIO load type"),
                            }
                        },
                        irq.MMIO.Offset...irq.MMIO.OffsetEnd - 1 => {
                            switch (T) {
                                u16, u32 => return irq.load_mmio_generic(T, psx, offset),
                                else => @panic("Invalid IRQ MMIO load type"),
                            }
                        },
                        dma.MMIO.Offset...dma.MMIO.OffsetEnd - 1 => {
                            return dma.load_mmio_generic(T, psx, offset);
                        },
                        timers.MMIO.Offset...timers.MMIO.OffsetEnd - 1 => {
                            return timers.load_mmio_generic(T, psx, offset);
                        },
                        cdrom.MMIO.Offset...cdrom.MMIO.OffsetEnd - 1 => {
                            switch (T) {
                                u8 => return cdrom.load_mmio_u8(psx, offset),
                                u16 => return cdrom.load_mmio_u16(psx, offset),
                                else => @panic("Invalid MMIO load type"),
                            }
                        },
                        gpu.MMIO.Offset...gpu.MMIO.OffsetEnd - 1 => {
                            switch (T) {
                                u32 => return gpu.load_mmio_u32(psx, offset),
                                else => @panic("Invalid MMIO load type"),
                            }
                        },
                        MDEC_MMIO.Offset...MDEC_MMIO.OffsetEnd - 1 => {
                            @panic("NOT IMPLEMENTED");
                        },
                        spu.MMIO.Offset...spu.MMIO.OffsetEnd - 1 => {
                            return spu.load_mmio_generic(T, psx, offset);
                        },
                        Expansion2_MMIO.Offset...Expansion2_MMIO.OffsetEnd - 1 => {
                            @panic("NOT IMPLEMENTED");
                        },
                        else => {
                            std.debug.print("offset = {x}\n", .{address.offset});
                            @panic("Invalid offset");
                        },
                    }
                },
                BIOS_Offset...BIOS_OffsetEnd - 1 => |offset| {
                    const local_offset = offset - BIOS_Offset;
                    const type_slice = psx.bios[local_offset..];
                    return std.mem.readInt(T, type_slice[0..type_bytes], .little);
                },
                Expansion_Offset...Expansion_OffsetEnd - 1 => |offset| switch (offset) {
                    Expansion_ParallelPortOffset => return 0xff,
                    else => unreachable,
                },
                Scratchpad_Offset...Scratchpad_OffsetEnd - 1 => |offset| {
                    std.debug.assert(address.mapping != .Kseg1);
                    const local_offset = offset - Scratchpad_Offset;
                    const type_slice = psx.scratchpad[local_offset..];
                    return std.mem.readInt(T, type_slice[0..type_bytes], .little);
                },
                else => {
                    std.debug.print("address = {x}\n", .{address.offset});
                    @panic("Invalid address");
                },
            }
        },
        .Kseg2 => {
            switch (address.offset) {
                CacheControl_Offset => {
                    if (config.enable_debug_print) {
                        std.debug.print("FIXME load ignored at cache control offset\n", .{});
                    }
                    return 0;
                },
                else => unreachable,
            }
        },
    }
}

fn store_generic(comptime T: type, psx: *PSXState, address: PSXAddress, value: T) void {
    const type_info = @typeInfo(T);
    const type_bits = type_info.int.bits;
    const type_bytes = type_bits / 8;

    std.debug.assert(type_info.int.signedness == .unsigned);
    std.debug.assert(type_bits % 8 == 0);

    if (config.enable_debug_print) {
        std.debug.print("store addr: 0x{x:0>8}\n", .{@as(u32, @bitCast(address))});

        // {{ and }} are escaped curly brackets
        const type_format_string = std.fmt.comptimePrint("0x{{x:0>{}}}", .{type_bytes * 2});
        std.debug.print("store value: " ++ type_format_string ++ "\n", .{value});
    }

    if (psx.cpu.regs.sr.isolate_cache == 1) {
        if (config.enable_debug_print) {
            std.debug.print("FIXME store ignored because of cache isolation\n", .{});
        }
        return;
    }

    std.debug.assert(address.offset % type_bytes == 0);

    switch (address.mapping) {
        .Useg, .Kseg0, .Kseg1 => {
            switch (address.offset) {
                RAM_Offset...RAM_OffsetEnd - 1 => |offset| {
                    const local_offset = offset - RAM_Offset;
                    const type_slice = psx.ram[local_offset..];
                    std.mem.writeInt(T, type_slice[0..type_bytes], value, .little);
                },
                MMIO_Offset...MMIO_OffsetEnd - 1 => |offset| {
                    switch (offset) {
                        memory_control1.MMIO.Offset...memory_control1.MMIO.OffsetEnd - 1 => {
                            switch (T) {
                                u32 => memory_control1.store_mmio_u32(psx, offset, value),
                                else => @panic("Invalid MC1 MMIO store type"),
                            }
                        },
                        IOPorts_MMIO.Offset...IOPorts_MMIO.OffsetEnd - 1 => {
                            std.debug.print("FIXME IOPorts store ignored at offset {x}\n", .{offset});
                        },
                        memory_control2.MMIO.Offset...memory_control2.MMIO.OffsetEnd - 1 => {
                            switch (T) {
                                u16, u32 => return memory_control2.store_mmio_generic(T, psx, offset, value),
                                else => @panic("Invalid MC2 MMIO store type"),
                            }
                        },
                        irq.MMIO.Offset...irq.MMIO.OffsetEnd - 1 => {
                            switch (T) {
                                u16, u32 => return irq.store_mmio_generic(T, psx, offset, value),
                                else => @panic("Invalid IRQ MMIO store type"),
                            }
                        },
                        dma.MMIO.Offset...dma.MMIO.OffsetEnd - 1 => {
                            dma.store_mmio_generic(T, psx, offset, value);
                        },
                        timers.MMIO.Offset...timers.MMIO.OffsetEnd - 1 => {
                            timers.store_mmio_generic(T, psx, offset, value);
                        },
                        cdrom.MMIO.Offset...cdrom.MMIO.OffsetEnd - 1 => {
                            switch (T) {
                                u8 => cdrom.store_mmio_u8(psx, offset, value),
                                else => @panic("Invalid MMIO store type"),
                            }
                        },
                        gpu.MMIO.Offset...gpu.MMIO.OffsetEnd - 1 => {
                            switch (T) {
                                u32 => gpu.store_mmio_u32(psx, offset, value),
                                else => @panic("Invalid MMIO store type"),
                            }
                        },
                        MDEC_MMIO.Offset...MDEC_MMIO.OffsetEnd - 1 => {
                            if (config.enable_debug_print) {
                                std.debug.print("FIXME store ignored\n", .{});
                            }
                        },
                        spu.MMIO.Offset...spu.MMIO.OffsetEnd - 1 => {
                            spu.store_mmio_generic(T, psx, offset, value);
                        },
                        Expansion2_MMIO.Offset...Expansion2_MMIO.OffsetEnd - 1 => {
                            if (config.enable_debug_print) {
                                std.debug.print("FIXME store ignored\n", .{});
                            }
                        },
                        else => {
                            std.debug.print("offset {x}\n", .{offset});
                            @panic("Offset out of range");
                        },
                    }
                },
                BIOS_Offset...BIOS_OffsetEnd - 1 => unreachable, // This should be read-only
                Scratchpad_Offset...Scratchpad_OffsetEnd - 1 => |offset| {
                    std.debug.assert(address.mapping != .Kseg1);
                    const local_offset = offset - Scratchpad_Offset;
                    const type_slice = psx.scratchpad[local_offset..];
                    std.mem.writeInt(T, type_slice[0..type_bytes], value, .little);
                },
                else => {
                    std.debug.print("address = {x}\n", .{address.offset});
                    unreachable; // This should be read-only
                },
            }
        },
        .Kseg2 => {
            switch (address.offset) {
                CacheControl_Offset => {
                    if (config.enable_debug_print) {
                        std.debug.print("FIXME store ignored at offset\n", .{});
                    }
                },
                else => unreachable,
            }
        },
    }
}

// KUSEG       KSEG0     KSEG1 Length Description
// 0x00000000 0x80000000 0xa0000000 2048K Main RAM
pub const RAM_SizeBytes = 2 * 1024 * 1024;
pub const RAM_Offset = 0x00000000;
const RAM_OffsetEnd = RAM_Offset + RAM_SizeBytes;

// 0x1f000000 0x9f000000 0xbf000000 8192K Expansion Region 1
const Expansion_SizeBytes = 8 * 1024 * 1024;
const Expansion_Offset = 0x1f000000;
const Expansion_OffsetEnd = Expansion_Offset + Expansion_SizeBytes;

const Expansion_ParallelPortOffset = 0x1f00_0084;

// 0x1f800000 0x9f800000 0xbf800000 1K Scratchpad
pub const Scratchpad_SizeBytes = 1024;
const Scratchpad_Offset = 0x1f800000;
const Scratchpad_OffsetEnd = Scratchpad_Offset + Scratchpad_SizeBytes;

// 0x1fc00000 0x9fc00000 0xbfc00000 512K BIOS ROM
pub const BIOS_SizeBytes = 512 * 1024;
const BIOS_Offset = 0x1fc00000;
const BIOS_OffsetEnd = BIOS_Offset + BIOS_SizeBytes;

// 0x1ffe0130constant
const CacheControl_Offset = 0x1ffe0130;

// 0x1f801000 0x9f801000 0xbf801000 8K Hardware registers
const MMIO_SizeBytes = 8 * 1024;
pub const MMIO_Offset = 0x1f801000;
const MMIO_OffsetEnd = MMIO_Offset + MMIO_SizeBytes;
pub const MMIO = packed struct {
    memory_control1: memory_control1.MMIO.Packed = .{},
    io_ports: IOPorts_MMIO.Packed = .{},
    memory_control2: memory_control2.MMIO.Packed = .{},
    irq: irq.MMIO.Packed = .{},
    dma: dma.MMIO.Packed = .{},
    timers: timers.MMIO.Packed = .{},
    cdrom: cdrom.MMIO.Packed = .{},
    gpu: gpu.MMIO.Packed = .{},
    mdec: MDEC_MMIO.Packed = .{},
    spu: spu.MMIO.Packed = .{},
    expansion2: Expansion2_MMIO.Packed = .{},
};

pub const IOPorts_MMIO = struct {
    pub const Offset = 0x1f801040;
    pub const OffsetEnd = Offset + SizeBytes;

    const SizeBytes = memory_control2.MMIO.Offset - Offset;

    comptime {
        std.debug.assert(@sizeOf(Packed) == SizeBytes);
    }

    pub const Joy_RX_TX_Offset = 0x1f801040;
    pub const Joy_Ctrl_Offset = 0x1f80104a;

    pub const Packed = packed struct {
        _unused: u256 = undefined,
    };
};

pub const MDEC_MMIO = struct {
    pub const Offset = 0x1f801820;
    pub const OffsetEnd = Offset + SizeBytes;

    const SizeBytes = spu.MMIO.Offset - Offset;

    comptime {
        std.debug.assert(@sizeOf(Packed) == SizeBytes);
    }

    pub const Packed = packed struct {
        _unused: u7936 = undefined,
    };
};

pub const Expansion2_MMIO = struct {
    pub const Offset = 0x1f802000;
    pub const OffsetEnd = Offset + SizeBytes;

    const SizeBytes = MMIO_OffsetEnd - Offset;

    comptime {
        std.debug.assert(@sizeOf(Packed) == SizeBytes);
    }

    pub const UnknownDebug_Offset = 0x1f802041;

    pub const Packed = packed struct {
        // FIXME Abusing the compiler for 1 bit here, one more and we hit the limit.
        // Really it should be 32768.
        _unused: u32767 = undefined,
    };
};

comptime {
    // Assert that the layout of the MMIO struct is correct, otherwise all hell breaks loose
    std.debug.assert(@offsetOf(MMIO, "memory_control1") == memory_control1.MMIO.Offset - MMIO_Offset);
    std.debug.assert(@offsetOf(MMIO, "io_ports") == IOPorts_MMIO.Offset - MMIO_Offset);
    std.debug.assert(@offsetOf(MMIO, "memory_control2") == memory_control2.MMIO.Offset - MMIO_Offset);
    std.debug.assert(@offsetOf(MMIO, "irq") == irq.MMIO.Offset - MMIO_Offset);
    std.debug.assert(@offsetOf(MMIO, "dma") == dma.MMIO.Offset - MMIO_Offset);
    std.debug.assert(@offsetOf(MMIO, "timers") == timers.MMIO.Offset - MMIO_Offset);
    std.debug.assert(@offsetOf(MMIO, "cdrom") == cdrom.MMIO.Offset - MMIO_Offset);
    std.debug.assert(@offsetOf(MMIO, "gpu") == gpu.MMIO.Offset - MMIO_Offset);
    std.debug.assert(@offsetOf(MMIO, "mdec") == MDEC_MMIO.Offset - MMIO_Offset);
    std.debug.assert(@offsetOf(MMIO, "spu") == spu.MMIO.Offset - MMIO_Offset);
    std.debug.assert(@offsetOf(MMIO, "expansion2") == Expansion2_MMIO.Offset - MMIO_Offset);

    std.debug.assert(@sizeOf(MMIO) == MMIO_SizeBytes);
}
