const std = @import("std");

const CPUState = @import("cpu/state.zig").CPUState;
const gpu = @import("gpu/state.zig");
const mmio = @import("mmio.zig");
const cdrom = @import("cdrom/state.zig");

pub const PSXState = struct {
    cpu: CPUState = .{},
    gpu: gpu.GPUState,
    cdrom: cdrom.CDROMState = .{},
    mmio: mmio.MMIO = .{},
    ram: []u8,
    bios: [mmio.BIOS_SizeBytes]u8,
    scratchpad: [mmio.Scratchpad_SizeBytes]u8,

    step_index: u64 = 0,
    headless: bool = true,

    pub fn write(self: @This(), writer: anytype) !void {
        try self.cpu.write(writer);
        try self.gpu.write(writer);
        try self.cdrom.write(writer);

        try writer.writeStruct(self.mmio);
        try writer.writeAll(self.ram);
        try writer.writeAll(&self.bios);
        try writer.writeAll(&self.scratchpad);

        try writer.writeInt(@TypeOf(self.step_index), self.step_index, .little);
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

        const scratchpad_bytes_written = try reader.readAll(&self.scratchpad);
        if (scratchpad_bytes_written != self.scratchpad.len) {
            return error.InvalidScratchPadSize;
        }

        self.step_index = try reader.readInt(@TypeOf(self.step_index), .little);
        self.headless = try reader.readByte() != 0;
    }
};

pub fn create_state(bios: [mmio.BIOS_SizeBytes]u8, allocator: std.mem.Allocator) !PSXState {
    const ram = try allocator.alloc(u8, mmio.RAM_SizeBytes);
    errdefer allocator.free(ram);

    return PSXState{
        .gpu = try gpu.create_gpu_state(allocator),
        .ram = ram,
        .bios = bios,
        .scratchpad = std.mem.zeroes([mmio.Scratchpad_SizeBytes]u8),
    };
}

pub fn destroy_state(psx: *PSXState, allocator: std.mem.Allocator) void {
    gpu.destroy_gpu_state(&psx.gpu, allocator);

    allocator.free(psx.ram);
}
