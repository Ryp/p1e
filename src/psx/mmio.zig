const std = @import("std");

const PSXState = @import("state.zig").PSXState;

const bus = @import("bus.zig");

pub const MMIO = packed struct {
    memory_control1: memory_control1.MMIO.Packed = .{},
    ports: ports.MMIO.Packed = .{},
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

pub fn get_mutable_mmio_slice(comptime T: type, psx: *PSXState, offset: u29) *[@typeInfo(T).int.bits / 8]u8 {
    const type_bytes = @typeInfo(T).int.bits / 8;

    const local_offset = offset - bus.MMIO_Offset;
    const mmio_bytes = std.mem.asBytes(&psx.mmio);
    const type_slice = mmio_bytes[local_offset..][0..type_bytes];

    return type_slice;
}

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

    const SizeBytes = bus.MMIO_OffsetEnd - Offset;

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
    std.debug.assert(@offsetOf(MMIO, "memory_control1") == memory_control1.MMIO.Offset - bus.MMIO_Offset);
    std.debug.assert(@offsetOf(MMIO, "ports") == ports.MMIO.Offset - bus.MMIO_Offset);
    std.debug.assert(@offsetOf(MMIO, "memory_control2") == memory_control2.MMIO.Offset - bus.MMIO_Offset);
    std.debug.assert(@offsetOf(MMIO, "irq") == irq.MMIO.Offset - bus.MMIO_Offset);
    std.debug.assert(@offsetOf(MMIO, "dma") == dma.MMIO.Offset - bus.MMIO_Offset);
    std.debug.assert(@offsetOf(MMIO, "timers") == timers.MMIO.Offset - bus.MMIO_Offset);
    std.debug.assert(@offsetOf(MMIO, "cdrom") == cdrom.MMIO.Offset - bus.MMIO_Offset);
    std.debug.assert(@offsetOf(MMIO, "gpu") == gpu.MMIO.Offset - bus.MMIO_Offset);
    std.debug.assert(@offsetOf(MMIO, "mdec") == MDEC_MMIO.Offset - bus.MMIO_Offset);
    std.debug.assert(@offsetOf(MMIO, "spu") == spu.MMIO.Offset - bus.MMIO_Offset);
    std.debug.assert(@offsetOf(MMIO, "expansion2") == Expansion2_MMIO.Offset - bus.MMIO_Offset);

    std.debug.assert(@sizeOf(MMIO) == bus.MMIO_SizeBytes);
}

const memory_control1 = @import("mmio_memory_control1.zig");
const memory_control2 = @import("mmio_memory_control2.zig");
const ports = @import("ports/mmio.zig");
const irq = @import("mmio_interrupts.zig");
const dma = @import("dma/mmio.zig");
const timers = @import("mmio_timers.zig");
const cdrom = @import("cdrom/mmio.zig");
const gpu = @import("gpu/mmio.zig");
const spu = @import("spu/mmio.zig");
