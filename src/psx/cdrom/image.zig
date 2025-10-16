const std = @import("std");

const native_os = @import("builtin").os.tag;

pub const CDROMImage = struct {
    file: std.fs.File,
    mapped_data: []align(std.heap.page_size_min) u8,
    sector_count: usize,
    sectors: []const RawSector,
};

pub fn open_cdrom_image_from_bin(cdrom_path: []const u8) !CDROMImage {
    var cdrom_image: CDROMImage = undefined;

    cdrom_image.file = if (std.fs.cwd().openFile(cdrom_path, .{ .mode = .read_only })) |f| f else |err| {
        std.debug.print("error: couldn't open CDROM file: '{s}'\n", .{cdrom_path});
        return err;
    };
    errdefer cdrom_image.file.close();

    const size_bytes = try cdrom_image.file.getEndPos();

    if (size_bytes % RawSectorSizeBytes != 0) {
        std.debug.print("error: loading '{s}': file size {} doesn't align on sector size\n", .{ cdrom_path, size_bytes });
        return error.InvalidCDROMSectorSize;
    }

    cdrom_image.sector_count = size_bytes / RawSectorSizeBytes;

    switch (native_os) {
        .linux, .macos => {
            cdrom_image.mapped_data = try std.posix.mmap(null, size_bytes, std.posix.PROT.READ, .{ .TYPE = .PRIVATE }, cdrom_image.file.handle, 0);
            errdefer std.posix.munmap(cdrom_image.mapped_data);
        },
        .windows => @panic("Unsupported OS"),
        else => @panic("Unsupported OS"),
    }

    cdrom_image.sectors = std.mem.bytesAsSlice(RawSector, cdrom_image.mapped_data);

    // Checking CDROM
    for (cdrom_image.sectors, 0..) |sector, sector_index| {
        if (sector.sync != RawSector.ValidSync) {
            std.debug.print("error: loading '{s}' at sector index {}: invalid sync value {x}\n", .{ cdrom_path, sector_index, sector.sync });
            return error.InvalidCDROMSectorSync;
        }

        var header_sector_index = msf_bcd_to_sector_index(sector.header.minute_bcd, sector.header.second_bcd, sector.header.frame_bcd) catch {
            std.debug.print("error: loading '{s}' at sector index {}: invalid MSF value in header {}:{}:{}\n", .{ cdrom_path, sector_index, sector.header.minute_bcd, sector.header.second_bcd, sector.header.frame_bcd });
            return error.InvalidCDROMSectorHeaderMSF;
        };

        if (header_sector_index < LeadInSectors) {
            std.debug.print("error: loading '{s}' at sector index {}: sector index {} in header is in lead-in area\n", .{ cdrom_path, sector_index, header_sector_index });
            return error.InvalidCDROMSectorHeaderLBA;
        }

        // Lead-in sectors are not included in BIN images but their MSF values are still taking them into account
        // FIXME Maybe this is just called PreGap and not Lead-In?
        header_sector_index -= LeadInSectors;

        if (header_sector_index != sector_index) {
            std.debug.print("error: loading '{s}' at sector index {}: mismatched sector_index {} in header\n", .{ cdrom_path, sector_index, header_sector_index });
            return error.InvalidCDROMSectorHeaderLBA;
        }

        if (sector.header.sector_mode != .Mode1 and sector.header.sector_mode != .Mode2) {
            std.debug.print("error: loading '{s}' at sector index {}: invalid sector mode {} \n", .{ cdrom_path, sector_index, sector.header.sector_mode });
            return error.InvalidCDROMSectorMode;
        }

        // FIXME
        // TODO Check ECC fields
        // TODO Check sub_header
        switch (sector.header.sector_mode) {
            .Mode0 => {
                std.debug.assert(sector.mode._0.zero == 0);
            },
            .Mode1 => {
                const mode1 = sector.mode._1;

                const crc_bytes = std.mem.asBytes(&sector)[@TypeOf(mode1).CRC32_OffsetStart..@TypeOf(mode1).CRC32_OffsetEnd];
                try check_cdrom_crc32(crc_bytes, mode1.edc_crc32);

                std.debug.assert(mode1.zero == 0);
            },
            .Mode2 => {
                const mode2 = sector.mode._2;
                std.debug.assert(mode2.sub_header == mode2.sub_header_copy);

                switch (mode2.sub_header.sub_mode.form) {
                    .Form1 => {
                        const form1 = mode2.form._1;

                        const crc_bytes = std.mem.asBytes(&sector)[@TypeOf(form1).CRC32_OffsetStart..@TypeOf(form1).CRC32_OffsetEnd];
                        try check_cdrom_crc32(crc_bytes, form1.edc_crc32);
                    },
                    .Form2 => {
                        const form2 = mode2.form._2;

                        if (form2.edc_crc32_optional != 0) {
                            const crc_bytes = std.mem.asBytes(&sector)[@TypeOf(form2).CRC32_OffsetStart..@TypeOf(form2).CRC32_OffsetEnd];
                            try check_cdrom_crc32(crc_bytes, form2.edc_crc32_optional);
                        }
                    },
                }
            },
            else => @panic("Invalid sector mode! Is this an audio track?"),
        }
    }

    return cdrom_image;
}

pub fn close_cdrom_image(cdrom_image: CDROMImage) void {
    switch (native_os) {
        .linux, .macos => {
            std.posix.munmap(cdrom_image.mapped_data);
        },
        .windows => @panic("Unsupported OS"),
        else => @panic("Unsupported OS"),
    }

    cdrom_image.file.close();
}

pub const RawSectorSizeBytes = 2352;
pub const FramesPerSeconds = 75;
pub const LeadInSectors = 2 * FramesPerSeconds;

// NOTE: The PSX mostly uses Mode2 sectors
//
// Audio sectors can be all audio (metadata is outside the sector in this case)
// EDC = Error Detection Code
// ECC = Error Correction Code
const RawSector = packed struct(u_bytes(RawSectorSizeBytes)) {
    sync: u_bytes(12), // Used to locate the start of a sector
    header: SectorHeader, // 4 bytes
    mode: packed union {
        _0: packed struct { // Mode0 - Empty
            zero: u_bytes(2336),
        },
        _1: packed struct(u_bytes(2336)) { // Mode1 (Original CDROM) - EDC + ECC
            data: u_bytes(2048),
            edc_crc32: u32,
            zero: u_bytes(8),
            ecc_reed_solomon: u_bytes(276),

            const CRC32_OffsetStart = 0x0;
            const CRC32_OffsetEnd = 0x810;
        },
        _2: packed struct(u_bytes(2336)) { // Mode2 aka CD-XA
            sub_header: Mode2SubHeader, // 4 bytes
            sub_header_copy: Mode2SubHeader, // 4 bytes
            form: packed union {
                _1: packed struct(u_bytes(2328)) { // Form1 - ECC + EDC
                    data: u_bytes(2048),
                    edc_crc32: u32,
                    ecc_reed_solomon: u_bytes(276),

                    const CRC32_OffsetStart = 0x10;
                    const CRC32_OffsetEnd = 0x818;
                },
                _2: packed struct(u_bytes(2328)) { // Form2 - ECC
                    data: u_bytes(2324),
                    edc_crc32_optional: u32, // Can be zero

                    const CRC32_OffsetStart = 0x10;
                    const CRC32_OffsetEnd = 0x92c;
                },
            },
        },
    },

    const ValidSync: u_bytes(12) = 0x00_ff_ff_ff_ff_ff_ff_ff_ff_ff_ff_00;
};

const SectorHeader = packed struct(u32) {
    minute_bcd: BCDByte,
    second_bcd: BCDByte,
    frame_bcd: BCDByte,
    sector_mode: enum(u8) {
        Mode0 = 0,
        Mode1 = 1,
        Mode2 = 2, // CD-XA
        _,
    },
};

const Mode2SubHeader = packed struct(u32) {
    file_number: u8,
    channel_number: u8,
    sub_mode: packed struct(u8) {
        a: u5,
        form: enum(u1) {
            Form1 = 0,
            Form2 = 1,
        },
        b: u2,
    },
    coding_info: u8,
};

// MSF = Minute Second Frame
// LBA = Logical Block Addressing (linear sector index)
pub fn msf_bcd_to_sector_index(minute_bcd: BCDByte, second_bcd: BCDByte, frame_bcd: BCDByte) !u32 {
    const minute = try bcd_to_int(minute_bcd);
    const second = try bcd_to_int(second_bcd);
    const frame = try bcd_to_int(frame_bcd);

    if (second >= 60) {
        return error.InvalidMSFSecond;
    }

    if (frame >= FramesPerSeconds) {
        return error.InvalidMSFFrame;
    }

    return msf_to_lba(minute, second, frame);
}

// BCD = Binary Coded Decimal
// Ex: 0x25 = 25
pub const BCDByte = packed struct(u8) {
    lo: u4,
    hi: u4,
};

fn bcd_to_int(bcd: BCDByte) !u8 {
    if (bcd.hi >= 10 or bcd.lo >= 10) {
        return error.InvalidBCDValue;
    }

    return @as(u8, bcd.hi) * 10 + bcd.lo;
}

fn msf_to_lba(minute: u32, second: u32, frame: u32) u32 {
    return minute * 60 * FramesPerSeconds + second * FramesPerSeconds + frame;
}

fn check_cdrom_crc32(bytes: []const u8, expected_crc32: u32) !void {
    const computed_crc32 = std.hash.crc.Crc32CdRomEdc.hash(bytes);

    if (computed_crc32 != expected_crc32) {
        std.debug.print("error: computed CRC32 0x{x} doesn't match header value 0x{x}\n", .{ computed_crc32, expected_crc32 });
        return error.InvalidCRC32Hash;
    }
}

// Helper for defining large backing types in bytes instead of bits.
fn u_bytes(bytes: comptime_int) type {
    return @Type(.{
        .int = .{
            .signedness = .unsigned,
            .bits = 8 * bytes,
        },
    });
}
