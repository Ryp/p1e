const std = @import("std");

const CPUState = @import("cpu/state.zig").CPUState;
const gpu = @import("gpu/state.zig");
const MMIO = @import("mmio.zig").MMIO;

pub const PSXState = struct {
    cpu: CPUState = .{},
    gpu: gpu.GPUState,
    mmio: MMIO = .{},
    ram: []u8,
    bios: [BIOS_SizeBytes]u8,
    headless: bool = true,
};

pub fn create_state(bios: [BIOS_SizeBytes]u8, allocator: std.mem.Allocator) !PSXState {
    const ram = try allocator.alloc(u8, RAM_SizeBytes);
    errdefer allocator.free(ram);

    return PSXState{
        .gpu = try gpu.create_gpu_state(allocator),
        .ram = ram,
        .bios = bios,
    };
}

pub fn destroy_state(psx: *PSXState, allocator: std.mem.Allocator) void {
    gpu.destroy_gpu_state(&psx.gpu, allocator);

    allocator.free(psx.ram);
}

pub const RAM_SizeBytes = 2 * 1024 * 1024;
pub const BIOS_SizeBytes = 512 * 1024;
