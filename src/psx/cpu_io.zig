const std = @import("std");

const cpu = @import("cpu.zig");
const PSXState = cpu.PSXState;

const dma = @import("dma.zig");
const timers = @import("mmio_timers.zig");
const gpu = @import("mmio_gpu.zig");

pub fn load_mem_u8(psx: *PSXState, address: u32) u8 {
    return load_mem_generic(u8, psx, @bitCast(address));
}

pub fn load_mem_u16(psx: *PSXState, address: u32) u16 {
    return load_mem_generic(u16, psx, @bitCast(address));
}

pub fn load_mem_u32(psx: *PSXState, address: u32) u32 {
    return load_mem_generic(u32, psx, @bitCast(address));
}

pub fn store_mem_u8(psx: *PSXState, address: u32, value: u8) void {
    store_mem_generic(u8, psx, @bitCast(address), value);
}

pub fn store_mem_u16(psx: *PSXState, address: u32, value: u16) void {
    store_mem_generic(u16, psx, @bitCast(address), value);
}

pub fn store_mem_u32(psx: *PSXState, address: u32, value: u32) void {
    store_mem_generic(u32, psx, @bitCast(address), value);
}

pub const PSXAddress = packed struct {
    offset: u29,
    mapping: enum(u3) {
        Useg = 0b000,
        Seg0 = 0b100,
        Seg1 = 0b101,
        Seg2 = 0b111,
    },
};

// FIXME does cache isolation has any impact here?
fn load_mem_generic(comptime T: type, psx: *PSXState, address: PSXAddress) T {
    const type_info = @typeInfo(T);
    const type_bits = type_info.Int.bits;
    const type_bytes = type_bits / 8;

    std.debug.assert(type_info.Int.signedness == .unsigned);
    std.debug.assert(type_bits % 8 == 0);

    if (cpu.enable_debug_print) {
        std.debug.print("load addr: 0x{x:0>8}\n", .{@as(u32, @bitCast(address))});
    }

    std.debug.assert(address.offset % type_bytes == 0);

    switch (address.mapping) {
        .Useg, .Seg0, .Seg1 => {
            switch (address.offset) {
                RAM_Offset...RAM_OffsetEnd - 1 => |offset| {
                    const local_offset = offset - RAM_Offset;
                    const type_slice = psx.ram[local_offset..];
                    return std.mem.readInt(T, type_slice[0..type_bytes], .little);
                },
                MMIO_Offset...MMIO_OffsetEnd - 1 => |offset| {
                    const local_offset = offset - MMIO_Offset;
                    const mmio_bytes = std.mem.asBytes(&psx.mmio);
                    const type_slice = mmio_bytes[local_offset..][0..type_bytes];

                    switch (offset) {
                        MMIO_InterruptMask_Offset,
                        MMIO_InterruptStatus_Offset,
                        MMIO_SPU_Offset...MMIO_SPU_OffsetEnd - 1,
                        => {
                            if (cpu.enable_debug_print) {
                                std.debug.print("FIXME load ignored\n", .{});
                            }
                            return 0;
                        },
                        dma.MMIO.Offset...dma.MMIO.OffsetEnd - 1 => {
                            return dma.load_mmio_generic(T, psx, offset);
                        },
                        timers.MMIO.Offset...timers.MMIO.OffsetEnd - 1 => {
                            return timers.load_mmio_generic(T, psx, offset);
                        },
                        gpu.MMIO.Offset...gpu.MMIO.OffsetEnd - 1 => {
                            return gpu.load_mmio_generic(T, psx, offset);
                        },
                        else => {
                            const value = std.mem.readInt(T, type_slice[0..type_bytes], .little);
                            std.debug.print("address {x} = {}\n", .{ offset, value });
                            unreachable;
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
                else => unreachable,
            }
        },
        .Seg2 => {
            switch (address.offset) {
                CacheControl_Offset => {
                    if (cpu.enable_debug_print) {
                        std.debug.print("FIXME load ignored at cache control offset\n", .{});
                    }
                    return 0;
                },
                else => unreachable,
            }
        },
    }
}

fn store_mem_generic(comptime T: type, psx: *PSXState, address: PSXAddress, value: T) void {
    const type_info = @typeInfo(T);
    const type_bits = type_info.Int.bits;
    const type_bytes = type_bits / 8;

    std.debug.assert(type_info.Int.signedness == .unsigned);
    std.debug.assert(type_bits % 8 == 0);

    if (cpu.enable_debug_print) {
        std.debug.print("store addr: 0x{x:0>8}\n", .{@as(u32, @bitCast(address))});

        // {{ and }} are escaped curly brackets
        const type_format_string = std.fmt.comptimePrint("0x{{x:0>{}}}", .{type_bytes * 2});
        std.debug.print("store value: " ++ type_format_string ++ "\n", .{value});
    }

    if (psx.registers.sr.isolate_cache == 1) {
        if (cpu.enable_debug_print) {
            std.debug.print("FIXME store ignored because of cache isolation\n", .{});
        }
        return;
    }

    std.debug.assert(address.offset % type_bytes == 0);

    switch (address.mapping) {
        .Useg, .Seg0, .Seg1 => {
            switch (address.offset) {
                RAM_Offset...RAM_OffsetEnd - 1 => |offset| {
                    const local_offset = offset - RAM_Offset;
                    const type_slice = psx.ram[local_offset..];
                    std.mem.writeInt(T, type_slice[0..type_bytes], value, .little);
                },
                MMIO_Offset...MMIO_OffsetEnd - 1 => |offset| {
                    switch (offset) {
                        MMIO_Expansion1BaseAddress_Offset,
                        MMIO_Expansion2BaseAddress_Offset,
                        MMIO_0x1f801008_Offset,
                        MMIO_0x1f801010_Offset,
                        MMIO_0x1f80100c_Offset,
                        MMIO_0x1f801014_Offset,
                        MMIO_0x1f801018_Offset,
                        MMIO_0x1f80101c_Offset,
                        MMIO_0x1f801020_Offset,
                        MMIO_0x1f801060_Offset,
                        MMIO_InterruptMask_Offset,
                        MMIO_InterruptStatus_Offset,
                        MMIO_SPU_Offset...MMIO_SPU_OffsetEnd - 1,
                        MMIO_UnknownDebug_Offset,
                        => {
                            if (cpu.enable_debug_print) {
                                std.debug.print("FIXME store ignored\n", .{});
                            }
                        },
                        dma.MMIO.Offset...dma.MMIO.OffsetEnd - 1 => {
                            dma.store_mmio_generic(T, psx, offset, value);
                        },
                        timers.MMIO.Offset...timers.MMIO.OffsetEnd - 1 => {
                            timers.store_mmio_generic(T, psx, offset, value);
                        },
                        gpu.MMIO.Offset...gpu.MMIO.OffsetEnd - 1 => {
                            std.debug.assert(T == u32);
                            gpu.store_mmio_u32(psx, offset, value);
                        },
                        else => {
                            std.debug.print("address = {x}\n", .{offset});
                            unreachable;
                        },
                    }
                },
                BIOS_Offset...BIOS_OffsetEnd - 1 => unreachable, // This should be read-only
                else => unreachable,
            }
        },
        .Seg2 => {
            switch (address.offset) {
                CacheControl_Offset => {
                    if (cpu.enable_debug_print) {
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
const RAM_Offset = 0x00000000;
const RAM_OffsetEnd = RAM_Offset + cpu.RAM_SizeBytes;

// 0x1f000000 0x9f000000 0xbf000000 8192K Expansion Region 1
const Expansion_SizeBytes = 8 * 1024 * 1024;
const Expansion_Offset = 0x1f000000;
const Expansion_OffsetEnd = Expansion_Offset + Expansion_SizeBytes;

const Expansion_ParallelPortOffset = 0x1f00_0084;

// 0x1f800000 0x9f800000 0xbf800000 1K Scratchpad
const Scratchpad_SizeBytes = 1024;
const Scratchpad_Offset = 0x1f800000;
const Scratchpad_OffsetEnd = Scratchpad_Offset + Scratchpad_SizeBytes;

// 0x1fc00000 0x9fc00000 0xbfc00000 512K BIOS ROM
const BIOS_Offset = 0x1fc00000;
const BIOS_OffsetEnd = BIOS_Offset + cpu.BIOS_SizeBytes;

// 0x1ffe0130constant
const CacheControl_Offset = 0x1ffe0130;

// 0x1f801000 0x9f801000 0xbf801000 8K Hardware registers
const MMIO_SizeBytes = 8 * 1024;
pub const MMIO_Offset = 0x1f801000;
const MMIO_OffsetEnd = MMIO_Offset + MMIO_SizeBytes;
pub const MMIO = packed struct {
    memory_control1: MMIO_MemoryControl1 = .{},
    io_ports: MMIO_IOPorts = .{},
    memory_control2: MMIO_MemoryControl2 = .{},
    interrupt_control: MMIO_IRQControl = .{},
    dma: dma.MMIO.Packed = .{},
    timers: timers.MMIO.Packed = .{},
    cdrom: MMIO_CDROM = .{},
    gpu: gpu.MMIO.Packed = .{},
    mdec: MMIO_MDEC = .{},
    spu: MMIO_SPU = .{},
    expansion2: MMIO_Expansion2 = .{},
};

const MMIO_MemoryControl1_Offset = 0x1f801000;
const MMIO_MemoryControl1_SizeBytes = MMIO_IOPorts_Offset - MMIO_MemoryControl1_Offset;
const MMIO_MemoryControl1 = packed struct {
    _unused: u512 = undefined,
};

const MMIO_IOPorts_Offset = 0x1f801040;
const MMIO_IOPorts_SizeBytes = MMIO_MemoryControl2_Offset - MMIO_IOPorts_Offset;
const MMIO_IOPorts = packed struct {
    _unused: u256 = undefined,
};

const MMIO_MemoryControl2_Offset = 0x1f801060;
const MMIO_MemoryControl2_SizeBytes = MMIO_IRQControl_Offset - MMIO_MemoryControl2_Offset;
const MMIO_MemoryControl2 = packed struct {
    ram_size: u32 = 0x0B88,
    _unused: u96 = undefined,
};

const MMIO_IRQControl_Offset = 0x1f801070;
const MMIO_IRQControl_SizeBytes = dma.MMIO.Offset - MMIO_IRQControl_Offset;
const MMIO_IRQControl = packed struct {
    control: u32 = undefined,
    mask: u32 = undefined,
    _unused: u64 = undefined,
};

pub const MMIO_CDROM_Offset = 0x1f801800;
const MMIO_CDROM_SizeBytes = gpu.MMIO.Offset - MMIO_CDROM_Offset;
const MMIO_CDROM = packed struct {
    _unused: u128 = undefined,
};

pub const MMIO_MDEC_Offset = 0x1f801820;
const MMIO_MDEC_SizeBytes = MMIO_SPU_Offset - MMIO_MDEC_Offset;
const MMIO_MDEC_OffsetEnd = MMIO_MDEC_Offset + MMIO_MDEC_SizeBytes;
const MMIO_MDEC = packed struct {
    _unused: u7936 = undefined,
};

const MMIO_SPU_Offset = 0x1f801c00;
const MMIO_SPU_SizeBytes = MMIO_Expansion2_Offset - MMIO_SPU_Offset;
const MMIO_SPU_OffsetEnd = MMIO_SPU_Offset + MMIO_SPU_SizeBytes;
const MMIO_SPU = packed struct {
    _unused: u8192 = undefined,
};

const MMIO_Expansion2_Offset = 0x1f802000;
const MMIO_Expansion2_SizeBytes = MMIO_OffsetEnd - MMIO_Expansion2_Offset;
const MMIO_Expansion2 = packed struct {
    // FIXME Abusing the compiler for 1 bit here, one more and we hit the limit.
    // Really it should be 32768.
    _unused: u32767 = undefined,
};

// Known offsets, see https://psx-spx.consoledev.net/iomap/
// for more details.
const MMIO_Expansion1BaseAddress_Offset = 0x1f801000;
const MMIO_Expansion2BaseAddress_Offset = 0x1f801004;

const MMIO_0x1f801008_Offset = 0x1f801008;
const MMIO_0x1f80100c_Offset = 0x1f80100c;
const MMIO_0x1f801010_Offset = 0x1f801010;
const MMIO_0x1f801014_Offset = 0x1f801014;
const MMIO_0x1f801018_Offset = 0x1f801018;
const MMIO_0x1f80101c_Offset = 0x1f80101c;
const MMIO_0x1f801020_Offset = 0x1f801020;
const MMIO_0x1f801060_Offset = 0x1f801060;

const MMIO_InterruptStatus_Offset = 0x1f801070;
const MMIO_InterruptMask_Offset = 0x1f801074;

const MMIO_MainVolume_Left = 0x1f801d80;
const MMIO_MainVolume_Right = 0x1f801d82;

const MMIO_UnknownDebug_Offset = 0x1f802041;

comptime {
    // Assert that the layout of the MMIO struct is correct, otherwise all hell breaks loose
    std.debug.assert(@offsetOf(MMIO, "memory_control1") == MMIO_MemoryControl1_Offset - MMIO_Offset);
    std.debug.assert(@offsetOf(MMIO, "io_ports") == MMIO_IOPorts_Offset - MMIO_Offset);
    std.debug.assert(@offsetOf(MMIO, "memory_control2") == MMIO_MemoryControl2_Offset - MMIO_Offset);
    std.debug.assert(@offsetOf(MMIO, "interrupt_control") == MMIO_IRQControl_Offset - MMIO_Offset);
    std.debug.assert(@offsetOf(MMIO, "dma") == dma.MMIO.Offset - MMIO_Offset);
    std.debug.assert(@offsetOf(MMIO, "timers") == timers.MMIO.Offset - MMIO_Offset);
    std.debug.assert(@offsetOf(MMIO, "cdrom") == MMIO_CDROM_Offset - MMIO_Offset);
    std.debug.assert(@offsetOf(MMIO, "gpu") == gpu.MMIO.Offset - MMIO_Offset);
    std.debug.assert(@offsetOf(MMIO, "mdec") == MMIO_MDEC_Offset - MMIO_Offset);
    std.debug.assert(@offsetOf(MMIO, "spu") == MMIO_SPU_Offset - MMIO_Offset);
    std.debug.assert(@offsetOf(MMIO, "expansion2") == MMIO_Expansion2_Offset - MMIO_Offset);

    std.debug.assert(@sizeOf(MMIO_MemoryControl1) == MMIO_MemoryControl1_SizeBytes);
    std.debug.assert(@sizeOf(MMIO_IOPorts) == MMIO_IOPorts_SizeBytes);
    std.debug.assert(@sizeOf(MMIO_MemoryControl2) == MMIO_MemoryControl2_SizeBytes);
    std.debug.assert(@sizeOf(MMIO_IRQControl) == MMIO_IRQControl_SizeBytes);
    std.debug.assert(@sizeOf(MMIO_CDROM) == MMIO_CDROM_SizeBytes);
    std.debug.assert(@sizeOf(MMIO_MDEC) == MMIO_MDEC_SizeBytes);
    std.debug.assert(@sizeOf(MMIO_SPU) == MMIO_SPU_SizeBytes);
    std.debug.assert(@sizeOf(MMIO_Expansion2) == MMIO_Expansion2_SizeBytes);

    std.debug.assert(@sizeOf(MMIO) == MMIO_SizeBytes);
}
