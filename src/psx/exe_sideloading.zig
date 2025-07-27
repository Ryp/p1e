const std = @import("std");

const state = @import("state.zig");
const cpu_state = @import("cpu/state.zig");
const PSXState = state.PSXState;

const mmio = @import("mmio.zig");
const PSXAddress = mmio.PSXAddress;

pub const DefaultSideLoadingPC = 0x80030000;

const Header = packed struct(u448) {
    magic: Magic, // 000h-007h ASCII ID "PS-X EXE"
    zero: u64, //  008h-00Fh Zerofilled
    pc: u32, //  010h      Initial PC                   (usually 80010000h, or higher)
    gp: u32, //  014h      Initial GP/R28               (usually 0)
    ram_dst_addr: PSXAddress, //  018h      Destination Address in RAM   (usually 80010000h, or higher)
    exe_size_bytes: u32, //  01Ch      Filesize (must be N*800h)    (excluding 800h-byte header)
    data_section_offset: u32, //  020h      Data section Start Address   (usually 0)
    data_section_size_bytes: u32, //  024h      Data Section Size in bytes   (usually 0)
    bss_section_offset: u32, //  028h      BSS section Start Address    (usually 0) (when below Size=None)
    bss_section_size_bytes: u32, //  02Ch      BSS section Size in bytes    (usually 0) (0=None)
    sp_fp_base: u32, //  030h      Initial SP/R29 & FP/R30 Base (usually 801FFFF0h) (or 0=None)
    sp_fp_offset: u32, //  034h      Initial SP/R29 & FP/R30 Offs (usually 0, added to above Base)
};

const BinaryOffset = 0x800;

const Magic = packed struct(u64) {
    id0: u8 = 'P',
    id1: u8 = 'S',
    id2: u8 = '-',
    id3: u8 = 'X',
    id4: u8 = ' ',
    id5: u8 = 'E',
    id6: u8 = 'X',
    id7: u8 = 'E',
};

// FIXME little endian is forced here
pub fn load(psx: *PSXState, reader: anytype) !void {
    comptime {
        const native_endian = @import("builtin").target.cpu.arch.endian();
        if (native_endian != .little) {
            @compileError("This code assumes a little-endian system, please adjust accordingly.");
        }
    }

    const header = try reader.readStruct(Header);
    const default_magic = Magic{};

    if (header.magic != default_magic) {
        return error.InvalidMagic;
    }

    std.debug.print("HEADER = {}\n", .{header});

    // Skip the rest of the header until the RAM content
    try reader.skipBytes(BinaryOffset - @sizeOf(Header), .{});

    const ram_at_load_offset = psx.ram[header.ram_dst_addr.offset - mmio.RAM_Offset ..][0..header.exe_size_bytes];

    _ = try reader.readAll(ram_at_load_offset);

    psx.cpu.regs.pc = header.pc;
    psx.cpu.regs.next_pc = header.pc + 4;

    const gp_index = @intFromEnum(cpu_state.RegisterName.gp);
    psx.cpu.regs.r_in[gp_index] = header.gp;
    psx.cpu.regs.r_out[gp_index] = header.gp;

    if (header.sp_fp_base != 0) {
        const sp_fp_offset = header.sp_fp_base + header.sp_fp_offset;

        const sp_index = @intFromEnum(cpu_state.RegisterName.sp);
        psx.cpu.regs.r_in[sp_index] = sp_fp_offset;
        psx.cpu.regs.r_out[sp_index] = sp_fp_offset;

        const fp_index = @intFromEnum(cpu_state.RegisterName.fp);
        psx.cpu.regs.r_in[fp_index] = sp_fp_offset;
        psx.cpu.regs.r_out[fp_index] = sp_fp_offset;
    }

    // Unsupported fields
    std.debug.assert(header.data_section_size_bytes == 0);
    std.debug.assert(header.bss_section_size_bytes == 0);
}
