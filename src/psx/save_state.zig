const std = @import("std");

const psx_state = @import("state.zig");

const Magic = "P1ES"; // PlayStation 1 Emulator Save
const VersionMajor = 0;
const VersionMinor = 1;
const VersionPatch = 0;

// FIXME do somthing with this
const Header = packed struct {
    magic_0: u8 = Magic[0],
    magic_1: u8 = Magic[1],
    magic_2: u8 = Magic[2],
    magic_3: u8 = Magic[3],
    version: packed struct {
        major: u8 = VersionMajor,
        minor: u8 = VersionMinor,
        patch: u8 = VersionPatch,
        _zero: u8 = 0,
    } = .{},
};

// FIXME handle errors properly
pub fn save(psx: psx_state.PSXState, writer: anytype) !void {
    const header: Header = .{};

    try writer.writeStruct(header);

    try psx.write(writer);

    std.debug.print("Saved state with version: {}.{}.{}\n", .{
        header.version.major,
        header.version.minor,
        header.version.patch,
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

    if (header.version.major > VersionMajor) {
        std.debug.print("Unsupported major version: {}, supports up to {}\n", .{ header.version.major, VersionMajor });
        return error.UnsupportedNewerMajorVersion;
    } else if (header.version.major < VersionMajor) {
        // FIXME
        std.debug.print("Unsupported major version: {}, version {}\n", .{ header.version.major, VersionMajor });
        return error.UnsupportedOlderMajorVersion;
    }

    try psx.read(reader);

    std.debug.print("Loaded state with version: {}.{}.{}\n", .{
        header.version.major,
        header.version.minor,
        header.version.patch,
    });
}

test "State serialization" {
    const allocator = std.heap.page_allocator;
    const bios = std.mem.zeroes([psx_state.BIOS_SizeBytes]u8);

    var psx = try psx_state.create_state(bios, allocator);
    defer psx_state.destroy_state(&psx, allocator);

    const BufferSize = 4096;
    var buffer: [BufferSize]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);

    try save(psx, stream.writer());

    stream.reset();

    var psx_2 = try psx_state.create_state(bios, allocator);
    defer psx_state.destroy_state(&psx_2, allocator);

    try load(&psx_2, stream.reader());

    try std.testing.expectEqual(psx.cpu, psx_2.cpu);
}
