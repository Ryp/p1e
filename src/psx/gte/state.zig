const std = @import("std");

pub const GTEState = struct {
    regs: GTERegisters = .{ .raw = .{} },

    pub fn write(self: @This(), writer: anytype) !void {
        try writer.writeStruct(self.regs.typed, .little);
    }

    pub fn read(self: *@This(), reader: anytype) !void {
        self.regs.typed = try reader.takeStruct(@TypeOf(self.regs.typed), .little);
    }
};

pub const GTERegisters = extern union {
    pub const DataRegister = enum(u5) {
        VX0_VY0, // cop2r0
        VZ0, // cop2r1
        VX1_VY1, // cop2r2
        VZ1, // cop2r3
        VX2_VY2, // cop2r4
        VZ2, // cop2r5
        RGBC, // cop2r6
        OTZ, // cop2r7
        IR0, // cop2r8
        IR1, // cop2r9
        IR2, // cop2r10
        IR3, // cop2r11
        SX0_SY0, // cop2r12
        SX1_SY1, // cop2r13
        SX2_SY2, // cop2r14
        SXP_SYP, // cop2r15
        SZ0, // cop2r16
        SZ1, // cop2r17
        SZ2, // cop2r18
        SZ3, // cop2r19
        RGB0, // cop2r20
        RGB1, // cop2r21
        RGB2, // cop2r22
        RES1, // cop2r23
        MAC0, // cop2r24
        MAC1, // cop2r25
        MAC2, // cop2r26
        MAC3, // cop2r27
        IRGB, // cop2r28
        ORGB, // cop2r29
        LZCS, // cop2r30
        LZCR, // cop2r31
    };

    pub const CtrlRegister = enum(u5) {
        RT11_RT12, // cop2r32
        RT13_RT21, // cop2r33
        RT22_RT23, // cop2r34
        RT31_RT32, // cop2r35
        RT33, // cop2r36
        TRX, // cop2r37
        TRY, // cop2r38
        TRZ, // cop2r39
        L11_L12, // cop2r40
        L13_L21, // cop2r41
        L22_L23, // cop2r42
        L31_L32, // cop2r43
        L33, // cop2r44
        RBK, // cop2r45
        GBK, // cop2r46
        BBK, // cop2r47
        LR1_LR2, // cop2r48
        LR3_LG1, // cop2r49
        LG2_LG3, // cop2r50
        LB1_LB2, // cop2r51
        LB3, // cop2r52
        RFC, // cop2r53
        GFC, // cop2r54
        BFC, // cop2r55
        OFX, // cop2r56
        OFY, // cop2r57
        H, // cop2r58
        DQA, // cop2r59
        DQB, // cop2r60
        ZSF3, // cop2r61
        ZSF4, // cop2r62
        FLAG, // cop2r63
    };

    pub const PosType = packed struct(u32) {
        x: i16,
        y: i16,
    };

    pub const Vector = packed struct(u64) {
        x: i16,
        y: i16,
        z: i16,
        _b16_31: u16 = 0,
    };

    pub const MatrixType = extern struct {
        m11: i16_q3f12, // cop2r32.lsbs=RT11 cop2r40.lsbs=L11 cop2r48.lsbs=LR1
        m12: i16_q3f12, // cop2r32.msbs=RT12 cop2r40.msbs=L12 cop2r48.msbs=LR2
        m13: i16_q3f12, // cop2r33.lsbs=RT13 cop2r41.lsbs=L13 cop2r49.lsbs=LR3
        m21: i16_q3f12, // cop2r33.msbs=RT21 cop2r41.msbs=L21 cop2r49.msbs=LG1
        m22: i16_q3f12, // cop2r34.lsbs=RT22 cop2r42.lsbs=L22 cop2r50.lsbs=LG2
        m23: i16_q3f12, // cop2r34.msbs=RT23 cop2r42.msbs=L23 cop2r50.msbs=LG3
        m31: i16_q3f12, // cop2r35.lsbs=RT31 cop2r43.lsbs=L31 cop2r51.lsbs=LB1
        m32: i16_q3f12, // cop2r35.msbs=RT32 cop2r43.msbs=L32 cop2r51.msbs=LB2
        m33: i16_q3f12, // cop2r36     =RT33 cop2r44     =L33 cop2r52     =LB3
        _b16_31: u16 = 0,
    };

    pub const Typed = extern struct {
        // 16bit Vectors (R/W)
        //
        //   Vector 0 (V0)         Vector 1 (V1)       Vector 2 (V2)       Vector 3 (IR)
        //   cop2r0.lsbs - VX0     cop2r2.lsbs - VX1   cop2r4.lsbs - VX2   cop2r9  - IR1
        //   cop2r0.msbs - VY0     cop2r2.msbs - VY1   cop2r4.msbs - VY2   cop2r10 - IR2
        //   cop2r1      - VZ0     cop2r3      - VZ1   cop2r5      - VZ2   cop2r11 - IR3
        //
        // All elements are signed 16bit. The IRn and VZn elements occupy a whole 32bit register, reading these registers returns the 16bit value sign-expanded to 32bit. Note: IRn can be also indirectly accessed via IRGB/ORGB registers.
        V0: Vector, // cop2r0 cop2r1 VX0 VY0 VZ0
        V1: Vector, // cop2r2 cop2r3 VX1 VY1 VZ1
        V2: Vector, // cop2r4 cop2r5 VX2 VY2 VZ2
        // Color Register and Color FIFO
        RGBC: ColorRGB8Code, // cop2r6 rw|CODE |B    |G    |R    | Color/code
        // Average Z Registers (ZSF3/ZSF4=Input, R/W) (OTZ=Result, R)
        // Used only for AVSZ3/AVSZ4 commands.
        OTZ: u16, // cop2r7 (R) |   |OTZ 0,16, 0| Average Z value (for Ordering Table)
        _cop2r7_b16_31: u16,
        // Interpolation Factor
        // Used as Output for RTPS/RTPT, and as Input for various commands.
        IR0: i16_q3f12, // cop2r8 rw|Sign       |IR0 1, 3,12| Intermediate value 0.
        _cop2r8_b16_31: u16,
        IR1: i16, // cop2r9
        _cop2r9_b16_31: u16,
        IR2: i16, // cop2r10
        _cop2r10_b16_31: u16,
        IR3: i16, // cop2r11
        _cop2r11_b16_31: u16,
        // Screen XYZ Coordinate FIFOs
        // SX,SY,SZ are used as Output for RTPS/RTPT. Additionally, SX,SY are used as Input for NCLIP, and SZ is used as Input for AVSZ3/AVSZ4.
        // The SZn Fifo has 4 stages (required for AVSZ4 command), the SXYn Fifo has only 3 stages, and a special mirrored register: SXYP is a mirror of SXY2, the difference is that writing to SXYP moves SXY2/SXY1 to SXY1/SXY0, whilst writing to SXY2 (or any other SXYn or SZn registers) changes only the written register, but doesn't move any other Fifo entries.
        S0: PosType, // cop2r12 rw|SY0 1,15, 0|SX0 1,15, 0| Screen XY fifo (older)
        S1: PosType, // cop2r13 rw|SY1 1,15, 0|SX1 1,15, 0| Screen XY fifo (old)
        S2: PosType, // cop2r14 rw|SY2 1,15, 0|SX2 1,15, 0| Screen XY fifo (new)
        SP: PosType, // cop2r15 rw|SYP 1,15, 0|SXP 1,15, 0| SXY2-mirror with move-on-write
        SZ0: u16, // cop2r16 rw|0,16, 0| Screen Z fifo (oldest)
        _cop2r16_b16_31: u16,
        SZ1: u16, // cop2r17 rw|0,16, 0| Screen Z fifo (older)
        _cop2r17_b16_31: u16,
        SZ2: u16, // cop2r18 rw|0,16, 0| Screen Z fifo (old)
        _cop2r18_b16_31: u16,
        SZ3: u16, // cop2r19 rw|0,16, 0| Screen Z fifo (new)
        _cop2r19_b16_31: u16,
        // Color Register and Color FIFO
        // RES1 seems to be unused... looks like an unused Fifo stage... RES1 is read/write-able... unlike SXYP (for SXYn Fifo) it does not mirror to RGB2, nor does it have a move-on-write function...
        RGB0: ColorRGB8Code, // cop2r20 rw|CD0  |B0   |G0   |R0   | Characteristic color fifo.
        RGB1: ColorRGB8Code, // cop2r21 rw|CD1  |B1   |G1   |R1   |
        RGB2: ColorRGB8Code, // cop2r22 rw|CD2  |B2   |G2   |R2   |
        RES1: u32, // cop2r23 Prohibited
        // MAC0 - Sum of Products Value 0 (R/W)
        // MAC1..MAC3 - Sum of Products Values 1-3 (R/W)
        MAC0: i32, // cop2r24 rw|MAC0 1,31,0            | Sum of products value 0
        MAC1: i32, // cop2r25 rw|MAC1 1,31,0            | Sum of products value 1
        MAC2: i32, // cop2r26 rw|MAC2 1,31,0            | Sum of products value 2
        MAC3: i32, // cop2r27 rw|MAC3 1,31,0            | Sum of products value 3
        // cop2r28 - IRGB - Color conversion Input (R/W)
        //
        // Expands 5:5:5 bit RGB (range 0..1Fh) to 16:16:16 bit RGB (range 0000h..0F80h).
        //
        //   0-4    Red   (0..1Fh) (R/W)  ;multiplied by 80h, and written to IR1
        //   5-9    Green (0..1Fh) (R/W)  ;multiplied by 80h, and written to IR2
        //   10-14  Blue  (0..1Fh) (R/W)  ;multiplied by 80h, and written to IR3
        //   15-31  Not used (always zero) (Read only)
        //
        // After writing to IRGB, the result can be read from IR3 after TWO nop's, and from IR1,IR2 after THREE nop's (for uncached code, ONE nop would work). When using IR1,IR2,IR3 as parameters for GTE commands, similar timing restrictions might apply... depending on when the specific commands use the parameters?
        IRGB: ColorRGB5_u32, // cop2r28
        // cop2r29 - ORGB - Color conversion Output (R)
        //
        // Collapses 16:16:16 bit RGB (range 0000h..0F80h) to 5:5:5 bit RGB (range 0..1Fh). Negative values (8000h..FFFFh/80h) are saturated to 00h, large positive values (1000h..7FFFh/80h) are saturated to 1Fh, there are no overflow or saturation flags set in cop2r63 though.
        //
        //   0-4    Red   (0..1Fh) (R)  ;IR1 divided by 80h, saturated to +00h..+1Fh
        //   5-9    Green (0..1Fh) (R)  ;IR2 divided by 80h, saturated to +00h..+1Fh
        //   10-14  Blue  (0..1Fh) (R)  ;IR3 divided by 80h, saturated to +00h..+1Fh
        //   15-31  Not used (always zero) (Read only)
        //
        // Any changes to IR1,IR2,IR3 are reflected to this register (and, actually also to IRGB) (ie. ORGB is simply a read-only mirror of IRGB).
        ORGB: ColorRGB5_u32, // cop2r29
        // cop2r30 - LZCS - Count Leading Bits Source data (R/W)
        // cop2r31 - LZCR - Count Leading Bits Result (R)
        //
        // Reading LZCR returns the leading 0 count of LZCS if LZCS is positive and
        // the leading 1 count of LZCS if LZCS is negative. The results are in range 1..32.
        LZCS: i32, // cop2r30
        LZCR: u32, // cop2r31
        RT: MatrixType, // Rotation matrix (RT)
        // Translation Vector (TR) (Input, R/W)
        //
        //   cop2r37 (cnt5) - TRX - Translation vector X
        //   cop2r38 (cnt6) - TRY - Translation vector Y
        //   cop2r39 (cnt7) - TRZ - Translation vector Z
        //
        // Each element is 32bit (1bit sign, 31bit integer).
        // Used only for MVMVA, RTPS, RTPT commands.
        TRX: i32_q31f0, // cop2r37
        TRY: i32_q31f0, // cop2r38
        TRZ: i32_q31f0, // cop2r39
        LLM: MatrixType, // Light matrix (LLM)
        // Background Color (BK) (Input, R/W)
        // Each element is 32bit (1bit sign, 19bit integer, 12bit fraction).
        RBK: i32_q19f12, // cop2r45 Background color red component
        GBK: i32_q19f12, // cop2r46 Background color green component
        BBK: i32_q19f12, // cop2r47 Background color blue component
        LCM: MatrixType, // Light Color matrix (LCM)
        // Far Color (FC) (Input, R/W)
        // Each element is 32bit (1bit sign, 27bit integer, 4bit fraction).
        RFC: i32_q27f4, // cop2r53 Far color red component
        GFC: i32_q27f4, // cop2r54 Far color green component
        BFC: i32_q27f4, // cop2r55 Far color blue component
        // Screen Offset and Distance (Input, R/W)
        //
        //   cop2r56 (cnt24) - OFX - Screen offset X
        //   cop2r57 (cnt25) - OFY - Screen offset Y
        //   cop2r58 (cnt26) - H   - Projection plane distance
        //   cop2r59 (cnt27) - DQA - Depth queing parameter A.(coeff.)
        //   cop2r60 (cnt28) - DQB - Depth queing parameter B.(offset.)
        //
        // The X and Y values are each 32bit (1bit sign, 15bit integer, 16bit fraction).
        // The H value is 16bit unsigned (0bit sign, 16bit integer, 0bit fraction). BUG: When reading the H register, the hardware does accidently \<sign-expand> the \<unsigned> 16bit value (ie. values +8000h..+FFFFh are returned as FFFF8000h..FFFFFFFFh) (this bug applies only to "mov rd,cop2r58" opcodes; the actual calculations via RTPS/RTPT opcodes are working okay).
        // The DQA value is only 16bit (1bit sign, 7bit integer, 8bit fraction).
        // The DQB value is 32bit (1bit sign, 7bit integer, 24bit? fraction).
        // Used only for RTPS/RTPT commands.
        OFX: i32_q15f16, // cop2r56
        OFY: i32_q15f16, // cop2r57
        H: u16, // cop2r58
        _cop2r58_b16_31: u16,
        DQA: i16_q7f8, // cop2r59
        _cop2r59_b16_31: u16,
        DQB: i32_q7f24, // cop2r60
        // Average Z Registers (ZSF3/ZSF4=Input, R/W) (OTZ=Result, R)
        //
        //   cop2r61 (cnt29) ZSF3 |  0|ZSF3 1,3,12| Z3 average scale factor (normally 1/3)
        //   cop2r62 (cnt30) ZSF4 |  0|ZSF4 1,3,12| Z4 average scale factor (normally 1/4)
        //
        // Used only for AVSZ3/AVSZ4 commands.
        ZSF3: i16_q3f12, // cop2r61
        _cop2r61_b16_31: u16,
        ZSF4: i16_q3f12, // cop2r62
        _cop2r62_b16_31: u16,
        // cop2r63 (cnt31) - FLAG - Returns any calculation errors.
        //
        // Maths overflows are indicated in FLAG register. In most cases, the result is saturated to MIN/MAX values (except MAC0,MAC1,MAC2,MAC3 which aren't saturated). For IR1,IR2,IR3 many commands allow to select the MIN value via "lm" bit of the GTE opcode (though for RTPS/RTPT, only the IR3 saturation flag (FLAG.22) always acts as if lm=0; the stored values of IR1, IR2, and IR3 all respect the lm bit).
        // cop2r63 (cnt31) - FLAG - Returns any calculation errors.
        // Bit30-12 are read/write-able, ie. they can be set/reset by software, however, that's normally not required - all bits are automatically reset at the begin of a new GTE command.
        // Bit31 is apparently intended for RTPS/RTPT commands, since it triggers only on flags that are affected by these two commands, but even for that commands it's totally useless since one could as well check if FLAG is nonzero.
        // Note: Writing 32bit values to 16bit GTE registers by software does not trigger any overflow/saturation flags (and does not do any saturation), eg. writing 12008900h (positive 32bit) to a signed 16bit register sets that register to FFFF8900h (negative 16bit).
        FLAG: packed struct(u32) { // cop2r63
            unused_b0_11: u12, //   0-11 Not used (always zero) (Read only)
            ir0_saturated: bool, // 12 IR0 saturated to +0000h..+1000h
            sy_saturated: bool, // 13 SY2 saturated to -0400h..+03FFh
            sx_saturated: bool, // 14 SX2 saturated to -0400h..+03FFh
            mac0_wrapped_negative: bool, // 15 MAC0 Result larger than 31 bits and negative
            mac0_wrapped_positive: bool, // 16 MAC0 Result larger than 31 bits and positive
            div_overflow: bool, // 17 Divide overflow. RTPS/RTPT division result saturated to max=1FFFFh
            sz_saturated: bool, // 18 SZ3 or OTZ saturated to +0000h..+FFFFh
            color_b_saturated: bool, // 19 Color-FIFO-B saturated to +00h..+FFh
            color_g_saturated: bool, // 20 Color-FIFO-G saturated to +00h..+FFh
            color_r_saturated: bool, // 21 Color-FIFO-R saturated to +00h..+FFh
            ir3_saturated: bool, // 22 IR3 saturated to +0000h..+7FFFh (lm=1) or to -8000h..+7FFFh (lm=0)
            ir2_saturated: bool, // 23 IR2 saturated to +0000h..+7FFFh (lm=1) or to -8000h..+7FFFh (lm=0)
            ir1_saturated: bool, // 24 IR1 saturated to +0000h..+7FFFh (lm=1) or to -8000h..+7FFFh (lm=0)
            mac3_wrapped_negative: bool, // 25 MAC3 Result larger than 43 bits and negative
            mac2_wrapped_negative: bool, // 26 MAC2 Result larger than 43 bits and negative
            mac1_wrapped_negative: bool, // 27 MAC1 Result larger than 43 bits and negative
            mac3_wrapped_positive: bool, // 28 MAC3 Result larger than 43 bits and positive
            mac2_wrapped_positive: bool, // 29 MAC2 Result larger than 43 bits and positive
            mac1_wrapped_positive: bool, // 30 MAC1 Result larger than 43 bits and positive
            err: bool, // 31 Error Flag (Bit30..23, and 18..13 ORed together) (Read only)
        },
    };

    // Init to zero even though on real HW it's probably just garbage
    raw: extern struct {
        data: [32]u32 = std.mem.zeroes([32]u32),
        ctrl: [32]u32 = std.mem.zeroes([32]u32),
    },
    typed: Typed,
};

comptime {
    std.debug.assert(@sizeOf(GTERegisters) == @sizeOf(u32) * 64);
}

pub const ColorRGB8Code = packed struct(u32) {
    r: u8,
    g: u8,
    b: u8,
    code: u8,
};

pub const ColorRGB5_u32 = packed struct(u32) {
    r: u5,
    g: u5,
    b: u5,
    _b15_31: u17 = 0,
};

const i16_q3f12 = i16;
const i16_q7f8 = i16;

const i32_q7f24 = i32;
const i32_q15f16 = i32;
const i32_q19f12 = i32;
const i32_q27f4 = i32;
const i32_q31f0 = i32;
