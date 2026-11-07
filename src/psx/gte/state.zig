const std = @import("std");

pub const GTEState = struct {
    regs: GTERegisters = .{},

    pub fn write(self: @This(), writer: anytype) !void {
        try writer.writeStruct(self.regs, .little);
    }

    pub fn read(self: *@This(), reader: anytype) !void {
        self.regs = try reader.takeStruct(@TypeOf(self.regs), .little);
    }
};

pub const GTERegisters = extern struct {
    pub const DataName = enum(u5) {
        VX0_VY0, // cop2r0
        VZ0, // cop2r1
        VX1_VY1, // cop2r2
        VZ1, // cop2r3
        VX2_VY2, // cop2r4
        VZ2, // cop2r5
        cop2r6, // cop2r6
        cop2r7, // cop2r7
        cop2r8, // cop2r8
        IR1, // cop2r9
        IR2, // cop2r10
        IR3, // cop2r11
        cop2r12, // cop2r12
        cop2r13, // cop2r13
        cop2r14, // cop2r14
        cop2r15, // cop2r15
        cop2r16, // cop2r16
        cop2r17, // cop2r17
        cop2r18, // cop2r18
        cop2r19, // cop2r19
        cop2r20, // cop2r20
        cop2r21, // cop2r21
        cop2r22, // cop2r22
        cop2r23, // cop2r23
        cop2r24, // cop2r24
        cop2r25, // cop2r25
        cop2r26, // cop2r26
        cop2r27, // cop2r27
        cop2r28, // cop2r28
        cop2r29, // cop2r29
        cop2r30, // cop2r30
        cop2r31, // cop2r31
    };

    pub const CtrlName = enum(u5) {
        cop2r32, // cop2r32
        cop2r33, // cop2r33
        cop2r34, // cop2r34
        cop2r35, // cop2r35
        cop2r36, // cop2r36
        cop2r37, // cop2r37
        cop2r38, // cop2r38
        cop2r39, // cop2r39
        cop2r40, // cop2r40
        cop2r41, // cop2r41
        cop2r42, // cop2r42
        cop2r43, // cop2r43
        cop2r44, // cop2r44
        cop2r45, // cop2r45
        cop2r46, // cop2r46
        cop2r47, // cop2r47
        cop2r48, // cop2r48
        cop2r49, // cop2r49
        cop2r50, // cop2r50
        cop2r51, // cop2r51
        cop2r52, // cop2r52
        cop2r53, // cop2r53
        cop2r54, // cop2r54
        cop2r55, // cop2r55
        OFX, // cop2r56
        OFY, // cop2r57
        H, // cop2r58
        DQA, // cop2r59
        DQB, // cop2r60
        ZSF3, // cop2r61
        ZSF4, // cop2r62
        FLAG, // cop2r63
    };

    // Init to zero even though on real HW it's probably just garbage
    data: extern union {
        raw: [32]u32,
        typed: extern struct {
            // 16bit Vectors (R/W)
            //
            //   Vector 0 (V0)         Vector 1 (V1)       Vector 2 (V2)       Vector 3 (IR)
            //   cop2r0.lsbs - VX0     cop2r2.lsbs - VX1   cop2r4.lsbs - VX2   cop2r9  - IR1
            //   cop2r0.msbs - VY0     cop2r2.msbs - VY1   cop2r4.msbs - VY2   cop2r10 - IR2
            //   cop2r1      - VZ0     cop2r3      - VZ1   cop2r5      - VZ2   cop2r11 - IR3
            //
            // All elements are signed 16bit. The IRn and VZn elements occupy a whole 32bit register, reading these registers returns the 16bit value sign-expanded to 32bit. Note: IRn can be also indirectly accessed via IRGB/ORGB registers.
            VX0: i16, // cop2r0
            VY0: i16, // cop2r0
            VZ0: i16, // cop2r1
            _cop2r1_b32_63: u16,
            VX1: i16, // cop2r2
            VY1: i16, // cop2r2
            VZ1: i16, // cop2r3
            _cop2r3_b32_63: u16,
            VX2: i16, // cop2r4
            VY2: i16, // cop2r4
            VZ2: i16, // cop2r5
            _cop2r5_b32_63: u16,
            // Color Register and Color FIFO
            //
            //   cop2r6  - RGBC  rw|CODE |B    |G    |R    | Color/code
            cop2r6: u32, // cop2r6
            // Average Z Registers (ZSF3/ZSF4=Input, R/W) (OTZ=Result, R)
            //
            //   cop2r7       OTZ (R) |   |OTZ 0,15, 0| Average Z value (for Ordering Table)
            //
            // Used only for AVSZ3/AVSZ4 commands.
            cop2r7: u32, // cop2r7
            // Interpolation Factor
            //
            //   cop2r8   IR0   rw|Sign       |IR0 1, 3,12| Intermediate value 0.
            //
            // Used as Output for RTPS/RTPT, and as Input for various commands.
            cop2r8: u32, // cop2r8
            IR1: i16, // cop2r9
            _cop2r9_b32_63: u16,
            IR2: i16, // cop2r10
            _cop2r10_b32_63: u16,
            IR3: i16, // cop2r11
            _cop2r11_b32_63: u16,
            // Screen XYZ Coordinate FIFOs
            //
            //   cop2r12 - SXY0  rw|SY0 1,15, 0|SX0 1,15, 0| Screen XY fifo (older)
            //   cop2r13 - SXY1  rw|SY1 1,15, 0|SX1 1,15, 0| Screen XY fifo (old)
            //   cop2r14 - SXY2  rw|SY2 1,15, 0|SX2 1,15, 0| Screen XY fifo (new)
            //   cop2r15 - SXYP  rw|SYP 1,15, 0|SXP 1,15, 0| SXY2-mirror with move-on-write
            //   cop2r16 - SZ0   rw|          0|SZ0 0,16, 0| Screen Z fifo (oldest)
            //   cop2r17 - SZ1   rw|          0|SZ1 0,16, 0| Screen Z fifo (older)
            //   cop2r18 - SZ2   rw|          0|SZ2 0,16, 0| Screen Z fifo (old)
            //   cop2r19 - SZ3   rw|          0|SZ3 0,16, 0| Screen Z fifo (new)
            //
            // SX,SY,SZ are used as Output for RTPS/RTPT. Additionally, SX,SY are used as Input for NCLIP, and SZ is used as Input for AVSZ3/AVSZ4.
            // The SZn Fifo has 4 stages (required for AVSZ4 command), the SXYn Fifo has only 3 stages, and a special mirrored register: SXYP is a mirror of SXY2, the difference is that writing to SXYP moves SXY2/SXY1 to SXY1/SXY0, whilst writing to SXY2 (or any other SXYn or SZn registers) changes only the written register, but doesn't move any other Fifo entries.
            cop2r12: u32, // cop2r12
            cop2r13: u32, // cop2r13
            cop2r14: u32, // cop2r14
            cop2r15: u32, // cop2r15
            cop2r16: u32, // cop2r16
            cop2r17: u32, // cop2r17
            cop2r18: u32, // cop2r18
            cop2r19: u32, // cop2r19
            // Color Register and Color FIFO
            //
            //   cop2r20 - RGB0  rw|CD0  |B0   |G0   |R0   | Characteristic color fifo.
            //   cop2r21 - RGB1  rw|CD1  |B1   |G1   |R1   |
            //   cop2r22 - RGB2  rw|CD2  |B2   |G2   |R2   |
            //   cop2r23 - (RES1)  |                       | Prohibited
            //
            // RES1 seems to be unused... looks like an unused Fifo stage... RES1 is read/write-able... unlike SXYP (for SXYn Fifo) it does not mirror to RGB2, nor does it have a move-on-write function...
            cop2r20: u32, // cop2r20
            cop2r21: u32, // cop2r21
            cop2r22: u32, // cop2r22
            cop2r23: u32, // cop2r23
            // MAC0 - Sum of Products Value 0 (R/W)
            //
            //   cop2r24  MAC0  rw|MAC0 1,31,0            | Sum of products value 0
            //
            // MAC1..MAC3 - Sum of Products Values 1-3 (R/W)
            //
            //   cop2r25  MAC1  rw|MAC1 1,31,0            | Sum of products value 1
            //   cop2r26  MAC2  rw|MAC2 1,31,0            | Sum of products value 2
            //   cop2r27  MAC3  rw|MAC3 1,31,0            | Sum of products value 3
            cop2r24: u32, // cop2r24
            cop2r25: u32, // cop2r25
            cop2r26: u32, // cop2r26
            cop2r27: u32, // cop2r27
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
            cop2r28: u32, // cop2r28
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
            cop2r29: u32, // cop2r29
            // cop2r30 - LZCS - Count Leading Bits Source data (R/W)
            // cop2r31 - LZCR - Count Leading Bits Result (R)
            //
            // Reading LZCR returns the leading 0 count of LZCS if LZCS is positive and the leading 1 count of LZCS if LZCS is negative. The results are in range 1..32.
            cop2r30: u32, // cop2r30
            cop2r31: u32, // cop2r31
        },
    } = .{ .raw = std.mem.zeroes([32]u32) },
    ctrl: extern union {
        raw: [32]u32,
        typed: extern struct {
            // Matrix Registers
            //
            //   Rotation matrix (RT)   Light matrix (LLM)     Light Color matrix (LCM)
            //   cop2r32.lsbs=RT11      cop2r40.lsbs=L11       cop2r48.lsbs=LR1
            //   cop2r32.msbs=RT12      cop2r40.msbs=L12       cop2r48.msbs=LR2
            //   cop2r33.lsbs=RT13      cop2r41.lsbs=L13       cop2r49.lsbs=LR3
            //   cop2r33.msbs=RT21      cop2r41.msbs=L21       cop2r49.msbs=LG1
            //   cop2r34.lsbs=RT22      cop2r42.lsbs=L22       cop2r50.lsbs=LG2
            //   cop2r34.msbs=RT23      cop2r42.msbs=L23       cop2r50.msbs=LG3
            //   cop2r35.lsbs=RT31      cop2r43.lsbs=L31       cop2r51.lsbs=LB1
            //   cop2r35.msbs=RT32      cop2r43.msbs=L32       cop2r51.msbs=LB2
            //   cop2r36     =RT33      cop2r44     =L33       cop2r52     =LB3
            //
            // Each element is 16bit (1bit sign, 3bit integer, 12bit fraction). Reading the last elements (RT33,L33,LB3) returns the 16bit value sign-expanded to 32bit.
            cop2r32: u32, // cop2r32
            cop2r33: u32, // cop2r33
            cop2r34: u32, // cop2r34
            cop2r35: u32, // cop2r35
            cop2r36: u32, // cop2r36
            // Translation Vector (TR) (Input, R/W)
            //
            //   cop2r37 (cnt5) - TRX - Translation vector X
            //   cop2r38 (cnt6) - TRY - Translation vector Y
            //   cop2r39 (cnt7) - TRZ - Translation vector Z
            //
            // Each element is 32bit (1bit sign, 31bit integer).
            // Used only for MVMVA, RTPS, RTPT commands.
            cop2r37: u32, // cop2r37
            cop2r38: u32, // cop2r38
            cop2r39: u32, // cop2r39
            cop2r40: u32, // cop2r40
            cop2r41: u32, // cop2r41
            cop2r42: u32, // cop2r42
            cop2r43: u32, // cop2r43
            cop2r44: u32, // cop2r44
            // Background Color (BK) (Input, R/W)
            //
            //   cop2r45 (cnt13) - RBK - Background color red component
            //   cop2r46 (cnt14) - GBK - Background color green component
            //   cop2r47 (cnt15) - BBK - Background color blue component
            //
            // Each element is 32bit (1bit sign, 19bit integer, 12bit fraction).
            cop2r45: u32, // cop2r45
            cop2r46: u32, // cop2r46
            cop2r47: u32, // cop2r47
            cop2r48: u32, // cop2r48
            cop2r49: u32, // cop2r49
            cop2r50: u32, // cop2r50
            cop2r51: u32, // cop2r51
            cop2r52: u32, // cop2r52
            // Far Color (FC) (Input, R/W)
            //
            //   cop2r53 (cnt21) - RFC - Far color red component
            //   cop2r54 (cnt22) - GFC - Far color green component
            //   cop2r55 (cnt23) - BFC - Far color blue component
            //
            // Each element is 32bit (1bit sign, 27bit integer, 4bit fraction).
            cop2r53: u32, // cop2r53
            cop2r54: u32, // cop2r54
            cop2r55: u32, // cop2r55
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
            _cop2r58_b32_63: u16,
            DQA: i16_q7f8, // cop2r59
            _cop2r59_b32_63: u16,
            DQB: i32_q7f24, // cop2r60
            // Average Z Registers (ZSF3/ZSF4=Input, R/W) (OTZ=Result, R)
            //
            //   cop2r61 (cnt29) ZSF3 |  0|ZSF3 1,3,12| Z3 average scale factor (normally 1/3)
            //   cop2r62 (cnt30) ZSF4 |  0|ZSF4 1,3,12| Z4 average scale factor (normally 1/4)
            //
            // Used only for AVSZ3/AVSZ4 commands.
            ZSF3: i16_q3f12, // cop2r61
            _cop2r61_b32_63: u16,
            ZSF4: i16_q3f12, // cop2r62
            _cop2r62_b32_63: u16,
            // cop2r63 (cnt31) - FLAG - Returns any calculation errors.
            //
            // See GTE Saturation chapter.
            // GTE Saturation
            //
            // Maths overflows are indicated in FLAG register. In most cases, the result is saturated to MIN/MAX values (except MAC0,MAC1,MAC2,MAC3 which aren't saturated). For IR1,IR2,IR3 many commands allow to select the MIN value via "lm" bit of the GTE opcode (though for RTPS/RTPT, only the IR3 saturation flag (FLAG.22) always acts as if lm=0; the stored values of IR1, IR2, and IR3 all respect the lm bit).
            // cop2r63 (cnt31) - FLAG - Returns any calculation errors.
            //
            //   0-11 Not used (always zero) (Read only)
            //   12   IR0 saturated to +0000h..+1000h
            //   13   SY2 saturated to -0400h..+03FFh
            //   14   SX2 saturated to -0400h..+03FFh
            //   15   MAC0 Result larger than 31 bits and negative
            //   16   MAC0 Result larger than 31 bits and positive
            //   17   Divide overflow. RTPS/RTPT division result saturated to max=1FFFFh
            //   18   SZ3 or OTZ saturated to +0000h..+FFFFh
            //   19   Color-FIFO-B saturated to +00h..+FFh
            //   20   Color-FIFO-G saturated to +00h..+FFh
            //   21   Color-FIFO-R saturated to +00h..+FFh
            //   22   IR3 saturated to +0000h..+7FFFh (lm=1) or to -8000h..+7FFFh (lm=0)
            //   23   IR2 saturated to +0000h..+7FFFh (lm=1) or to -8000h..+7FFFh (lm=0)
            //   24   IR1 saturated to +0000h..+7FFFh (lm=1) or to -8000h..+7FFFh (lm=0)
            //   25   MAC3 Result larger than 43 bits and negative
            //   26   MAC2 Result larger than 43 bits and negative
            //   27   MAC1 Result larger than 43 bits and negative
            //   28   MAC3 Result larger than 43 bits and positive
            //   29   MAC2 Result larger than 43 bits and positive
            //   30   MAC1 Result larger than 43 bits and positive
            //   31   Error Flag (Bit30..23, and 18..13 ORed together) (Read only)
            //
            // Bit30-12 are read/write-able, ie. they can be set/reset by software, however, that's normally not required - all bits are automatically reset at the begin of a new GTE command.
            // Bit31 is apparently intended for RTPS/RTPT commands, since it triggers only on flags that are affected by these two commands, but even for that commands it's totally useless since one could as well check if FLAG is nonzero.
            // Note: Writing 32bit values to 16bit GTE registers by software does not trigger any overflow/saturation flags (and does not do any saturation), eg. writing 12008900h (positive 32bit) to a signed 16bit register sets that register to FFFF8900h (negative 16bit).
            FLAG: packed struct(u32) { // cop2r63
                todo: u32,
            },
        },
    } = .{ .raw = std.mem.zeroes([32]u32) },
};

comptime {
    std.debug.assert(@sizeOf(GTERegisters) == @sizeOf(u32) * 64);
}

pub const i16_q3f12 = packed struct(u16) {
    pub const Shift = 12;

    value: i16,
};

pub const i16_q7f8 = packed struct(u16) {
    pub const Shift = 8;

    value: i16,
};

pub const i32_q15f16 = packed struct(u32) {
    pub const Shift = 16;

    value: i32,
};

pub const i32_q7f24 = packed struct(u32) {
    pub const Shift = 24;

    value: i32,
};
