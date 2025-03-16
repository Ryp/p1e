const MMIO = @import("mmio.zig").MMIO.Packed;

pub const CDROMState = struct {
    parameter_fifo: u8 = undefined, // FIXME not a FIFO obviously
    // volume_cd_L_to_spu_L: MMIO.Volume = .Normal,
    // volume_cd_L_to_spu_R: MMIO.Volume = .Normal,
    // volume_cd_R_to_spu_R: MMIO.Volume = .Normal,
    // volume_cd_R_to_spu_L: MMIO.Volume = .Normal,
};
