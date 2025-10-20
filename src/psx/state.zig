const std = @import("std");

const CPUState = @import("cpu/state.zig").CPUState;
const gte = @import("gte/state.zig");
const gpu = @import("gpu/state.zig");
const cdrom = @import("cdrom/state.zig");
const ports = @import("ports/state.zig");
const bus = @import("bus.zig");
const mmio = @import("mmio.zig");

pub const PSXState = struct {
    cpu: CPUState = .{},
    gte: gte.GTEState = .{},
    gpu: gpu.GPUState,
    cdrom: cdrom.CDROMState = .{},
    ports: ports.PortsState = .{},
    mmio: mmio.MMIO = .{},
    ram: []u8,
    bios: [bus.BIOS_SizeBytes]u8,
    scratchpad: [bus.Scratchpad_SizeBytes]u8,

    step_index: u64 = 0,
    headless: bool = true,

    // FIXME
    load_cdrom_path: ?[]const u8 = null,
    load_state_path: ?[]const u8 = null,
    save_state_path: ?[]const u8 = null,
    save_state_after_ticks: ?u64 = 0,
    load_exe_path: ?[]const u8 = null,
    skip_shell_execution: bool = false,

    pub fn write(self: @This(), writer: anytype) !void {
        try self.cpu.write(writer);
        try self.gte.write(writer);
        try self.gpu.write(writer);
        try self.cdrom.write(writer);
        try self.ports.write(writer);

        try writer.writeStruct(self.mmio);
        try writer.writeAll(self.ram);
        try writer.writeAll(&self.bios);
        try writer.writeAll(&self.scratchpad);

        try writer.writeInt(@TypeOf(self.step_index), self.step_index, .little);
        try writer.writeByte(if (self.headless) 1 else 0);
    }

    pub fn read(self: *@This(), reader: anytype) !void {
        try self.cpu.read(reader);
        try self.gte.read(reader);
        try self.gpu.read(reader);
        try self.cdrom.read(reader);
        try self.ports.read(reader);

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

pub fn create_state(bios: [bus.BIOS_SizeBytes]u8, allocator: std.mem.Allocator) !PSXState {
    const ram = try allocator.alloc(u8, bus.RAM_SizeBytes);
    errdefer allocator.free(ram);

    return PSXState{
        .gpu = try gpu.create_gpu_state(allocator),
        .ram = ram,
        .bios = bios,
        .scratchpad = std.mem.zeroes([bus.Scratchpad_SizeBytes]u8),
    };
}

pub fn destroy_state(psx: *PSXState, allocator: std.mem.Allocator) void {
    gpu.destroy_gpu_state(&psx.gpu, allocator);

    allocator.free(psx.ram);
}

test "Create and destroy" {
    const allocator = std.heap.page_allocator;
    const bios = std.mem.zeroes([bus.BIOS_SizeBytes]u8);

    var psx = try create_state(bios, allocator);
    defer destroy_state(&psx, allocator);
}
