const std = @import("std");
const assert = std.debug.assert;
const Md5 = std.crypto.hash.Md5;

const psx_state = @import("psx/state.zig");
const loop = @import("renderer/loop.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();
    // const allocator = std.heap.page_allocator;

    // Parse arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const embedded_bios = @embedFile("bios").*;

    var hash_bytes: [Md5.digest_length]u8 = undefined;
    Md5.hash(&embedded_bios, &hash_bytes, .{});

    const hash = std.mem.readInt(md5_scalar, &hash_bytes, .big);

    if (hash != scph1001_bin_md5) {
        std.debug.print("SCPH1001.BIN MD5 hash mismatch. Expected: {x}, got: {x}\n", .{ scph1001_bin_md5, hash });
        return error.InvalidBIOS;
    }

    var psx = try psx_state.create_state(embedded_bios, allocator);
    defer psx_state.destroy_state(&psx, allocator);

    try loop.run(&psx, allocator);
}

const md5_scalar = u128;
const scph1001_bin_md5: md5_scalar = 0x924e392ed05558ffdb115408c263dccf;

comptime {
    std.debug.assert(@sizeOf(md5_scalar) == Md5.digest_length);
}
