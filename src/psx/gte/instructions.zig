pub const GTECommand = packed struct(u25) {
    opcode: RealOpCode, // 0-5    Real GTE Command Number (00h..3Fh) (used by hardware)
    zero_b6_9: u4, // 6-9 Always zero                        (ignored by hardware)
    saturate_ir: bool, // 10     lm - Saturate IR1,IR2,IR3 result (0=To -8000h..+7FFFh, 1=To 0..+7FFFh)
    zero_b11_12: u2, // 11-12  Always zero                        (ignored by hardware)
    // 13-14  MVMVA Translation Vector (0=TR, 1=BK, 2=FC/Bugged, 3=None)
    mvmva_translation: enum(u2) {
        TR,
        BK,
        FC_Bugged,
        None,
    },
    // 15-16  MVMVA Multiply Vector    (0=V0, 1=V1, 2=V2, 3=IR/long)
    mvmva_vector: enum(u2) {
        V0,
        V1,
        V2,
        IR,
    },
    // 17-18  MVMVA Multiply Matrix    (0=Rotation. 1=Light, 2=Color, 3=Reserved)
    mvmva_matrix: enum(u2) {
        Rotation,
        Light,
        Color,
        Reserved,
    },
    shift_fraction: bool, // 19 sf - Shift Fraction in IR registers (0=No fraction, 1=12bit fraction)
    //  20-24  Fake GTE Command Number (00h..1Fh) (ignored by hardware)
    fake_opcode: u5,
};

pub const RealOpCode = enum(u6) {
    //              Clocks
    RTPS = 0x01, // 15  Perspective Transformation single
    RTPT = 0x30, // 23  Perspective Transformation triple
    MVMVA = 0x12, // 8   Multiply vector by matrix and add vector (see below)
    DCPL = 0x29, // 8   Depth Cue Color light
    DPCS = 0x10, // 8   Depth Cueing single
    DPCT = 0x2A, // 17  Depth Cueing triple (should be fake=08h, but isn't)
    INTPL = 0x11, // 8   Interpolation of a vector and far color vector
    SQR_sf = 0x28, // 5   Square of vector IR
    NCS = 0x1E, // 14  Normal color single
    NCT = 0x20, // 30  Normal color triple
    NCDS = 0x13, // 19  Normal color depth cue single vector
    NCDT = 0x16, // 44  Normal color depth cue triple vectors
    NCCS = 0x1B, // 17  Normal Color Color single vector
    NCCT = 0x3F, // 39  Normal Color Color triple vector
    CDP = 0x14, // 13  Color Depth Que
    CC = 0x1C, // 11  Color Color
    NCLIP = 0x06, // 8   Normal clipping
    AVSZ3 = 0x2D, // 5   Average of three Z values
    AVSZ4 = 0x2E, // 6   Average of four Z values
    OP_sf = 0x0C, // 6   Cross product of 2 vectors
    GPF_sf = 0x3D, // 5   General purpose interpolation
    GPL_sf = 0x3E, // 5   General purpose interpolation with base
    _,
};
