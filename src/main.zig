const std = @import("std");
const assert = std.debug.assert;
const Md5 = std.crypto.hash.Md5;

const psx_state = @import("psx/state.zig");
const cdrom = @import("psx/cdrom/image.zig");
const loop = @import("renderer/loop.zig");

const clap = @import("clap");
const tracy = @import("tracy.zig");
const builtin = @import("builtin");

var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
var gpa_allocator = std.heap.GeneralPurposeAllocator(.{}){};

pub fn main() !void {
    const gpa, const is_debug = switch (builtin.mode) {
        .Debug, .ReleaseSafe => .{ debug_allocator.allocator(), true },
        .ReleaseFast, .ReleaseSmall => .{ gpa_allocator.allocator(), false },
    };

    defer if (is_debug) {
        _ = debug_allocator.deinit();
    };

    if (tracy.enable_allocation) {
        var gpa_tracy = tracy.tracyAllocator(gpa);
        return main_with_allocator(gpa_tracy.allocator());
    }

    return main_with_allocator(gpa);
}

pub fn main_with_allocator(allocator: std.mem.Allocator) !void {
    const tr = tracy.trace(@src());
    defer tr.end();

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

    // First we specify what parameters our program can take.
    // We can use `parseParamsComptime` to parse a string into an array of `Param(Help)`.
    const params = comptime clap.parseParamsComptime(
        \\-h, --help                            Display this help and exit.
        \\-c, --load-cdrom-path <str>           Load CDROM in BIN format
        \\-l, --load-state-path <str>           Load state from file
        \\-s, --save-state-path <str>           Save state to file
        \\-t, --save-state-after-ticks <u64>    Save state after X ticks
        \\-e, --load-exe-path <str>             Load EXE from file
        \\-b, --skip-shell-execution            Skips shell execution
    );

    // Initialize our diagnostics, which can be used for reporting useful errors.
    // This is optional. You can also pass `.{}` to `clap.parse` if you don't
    // care about the extra information `Diagnostics` provides.
    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, clap.parsers.default, .{
        .diagnostic = &diag,
        .allocator = allocator,
    }) catch |err| {
        // Report useful error and exit.
        try diag.reportToFile(.stderr(), err);
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0) {
        return clap.usageToFile(.stdout(), clap.Help, &params);
    }

    psx.load_cdrom_path = res.args.@"load-cdrom-path";
    psx.load_state_path = res.args.@"load-state-path";
    psx.save_state_path = res.args.@"save-state-path";
    psx.save_state_after_ticks = res.args.@"save-state-after-ticks";
    psx.load_exe_path = res.args.@"load-exe-path";
    psx.skip_shell_execution = res.args.@"skip-shell-execution" != 0;

    if (psx.save_state_path) |save_state_path| {
        if (psx.save_state_after_ticks == null) {
            std.debug.print("You needs to specify ticks after setting for save state '{s}'\n", .{save_state_path});
            return error.InvalidArgument;
        }
    }

    if (psx.load_state_path) |load_state_path| {
        var exe_file = if (std.fs.cwd().openFile(load_state_path, .{})) |f| f else |err| {
            std.debug.print("Failed to open save state file '{s}': {}\n", .{ load_state_path, err });
            return err;
        };
        defer exe_file.close();

        const save_state = @import("psx/save_state.zig");

        save_state.load(&psx, exe_file.deprecatedReader()) catch |err| {
            std.debug.print("Failed to load save state file '{s}': {}\n", .{ load_state_path, err });
            return err;
        };

        std.debug.print("Loaded state from '{s}' at step {}\n", .{ load_state_path, psx.step_index });
    }

    // FIXME Improve CDROM loading
    if (psx.load_cdrom_path) |cdrom_path| {
        psx.cdrom.image = try cdrom.open_cdrom_image_from_bin(cdrom_path);
    }
    psx.cdrom.stat.is_shell_open = psx.cdrom.image == null;

    try loop.run(&psx, allocator);

    if (psx.cdrom.image) |cdrom_image| {
        cdrom.close_cdrom_image(cdrom_image);
    }
}

const md5_scalar = u128;
const scph1001_bin_md5: md5_scalar = 0x924e392ed05558ffdb115408c263dccf;

comptime {
    std.debug.assert(@sizeOf(md5_scalar) == Md5.digest_length);
}
