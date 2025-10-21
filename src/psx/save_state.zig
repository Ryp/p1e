const std = @import("std");

const psx_state = @import("state.zig");
const bus = @import("bus.zig");

const Magic = "P1ES"; // PlayStation 1 Emulator Save
const Version = 7; // Format version
const SupportedVersionMax = Version;
const SupportedVersionMin = Version;

const Header = packed struct(u64) {
    magic_0: u8 = Magic[0],
    magic_1: u8 = Magic[1],
    magic_2: u8 = Magic[2],
    magic_3: u8 = Magic[3],
    version: u32 = Version, // FIXME Not compatible with other endianness
};

// FIXME handle errors properly
pub fn save(psx: psx_state.PSXState, writer: anytype) !void {
    const header: Header = .{};

    try writer.writeStruct(header);

    try psx.write(writer);

    std.debug.print("Saved state with format version: {} at step {}\n", .{
        header.version,
        psx.step_index,
    });
}

// FIXME handle errors properly
pub fn load(psx: *psx_state.PSXState, reader: anytype) !void {
    const header: Header = try reader.readStruct(Header);
    const header_magic = [4]u8{ header.magic_0, header.magic_1, header.magic_2, header.magic_3 };

    if (!std.mem.eql(u8, &header_magic, Magic)) {
        std.debug.print("Invalid save state magic: {s}, expected {s}\n", .{ header_magic, Magic });
        return error.InvalidMagic;
    }

    if (header.version > SupportedVersionMax) {
        std.debug.print("Unsupported version: {}, supports up to {}\n", .{ header.version, SupportedVersionMax });
        return error.UnsupportedNewerVersion;
    } else if (header.version < SupportedVersionMin) {
        std.debug.print("Unsupported version: {}, supports from {}\n", .{ header.version, SupportedVersionMin });
        return error.UnsupportedOlderVersion;
    }

    try psx.read(reader);

    std.debug.print("Loaded state with format version: {} at step {}\n", .{
        header.version,
        psx.step_index,
    });
}

test "State serialization" {
    const allocator = std.heap.page_allocator;
    const bios = std.mem.zeroes([bus.BIOS_SizeBytes]u8);

    var psx = try psx_state.create_state(bios, allocator);
    defer psx_state.destroy_state(&psx, allocator);

    const BufferSize = 4 * 1024 * 1024; // 4 MiB buffer
    var buffer: [BufferSize]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);

    try save(psx, stream.writer());

    stream.reset();

    var psx_2 = try psx_state.create_state(bios, allocator);
    defer psx_state.destroy_state(&psx_2, allocator);

    try load(&psx_2, stream.reader());

    try std.testing.expectEqual(psx.cpu, psx_2.cpu);
    // try std.testing.expectEqual(psx.mmio, psx_2.mmio); // FIXME packed unions are a problem
    try std.testing.expectEqualSlices(u8, psx.ram, psx_2.ram);
    try std.testing.expectEqualSlices(u8, &psx.bios, &psx_2.bios);
}
