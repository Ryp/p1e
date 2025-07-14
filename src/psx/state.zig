const std = @import("std");

const CPUState = @import("cpu/state.zig").CPUState;
const gpu = @import("gpu/state.zig");
const MMIO = @import("mmio.zig").MMIO;
const cdrom = @import("cdrom/state.zig");

pub const PSXState = struct {
    cpu: CPUState = .{},
    gpu: gpu.GPUState,
    cdrom: cdrom.CDROMState = .{},
    mmio: MMIO = .{},
    ram: []u8,
    bios: [BIOS_SizeBytes]u8,
    headless: bool = true,

    pub fn write(self: @This(), writer: anytype) !void {
        try self.cpu.write(writer);
        try self.gpu.write(writer);
        try self.cdrom.write(writer);

        try writer.writeStruct(self.mmio);
        try writer.writeAll(self.ram);
        try writer.writeAll(&self.bios);

        try writer.writeByte(if (self.headless) 1 else 0);
    }

    pub fn read(self: *@This(), reader: anytype) !void {
        try self.cpu.read(reader);
        try self.gpu.read(reader);
        try self.cdrom.read(reader);

        self.mmio = try reader.readStruct(@TypeOf(self.mmio));

        const ram_bytes_written = try reader.readAll(self.ram);
        if (ram_bytes_written != self.ram.len) {
            return error.InvalidRAMSize;
        }

        const bios_bytes_written = try reader.readAll(&self.bios);
        if (bios_bytes_written != self.bios.len) {
            return error.InvalidBIOSSize;
        }

        self.headless = try reader.readByte() != 0;
    }
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
