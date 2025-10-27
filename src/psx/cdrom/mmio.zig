const std = @import("std");

const PSXState = @import("../state.zig").PSXState;
const config = @import("../config.zig");
const mmio_gpu = @import("../gpu/mmio.zig");

const execution = @import("execution.zig");

pub fn load_mmio_u8(psx: *PSXState, offset: u29) u8 {
    std.debug.assert(offset >= MMIO.Offset and offset < MMIO.OffsetEnd);

    if (config.enable_cdrom_debug) {
        std.debug.print("CDROM MMIO Load:  offset=0x{x} bank={} | ", .{ offset, psx.mmio.cdrom.index_status.index });
    }

    switch (offset) {
        MMIO.IndexStatus_Offset => {
            // Update status
            psx.mmio.cdrom.index_status.status = .{
                .ADPBUSY = false, // FIXME
                .PRMEMPT = psx.cdrom.parameter_fifo.is_empty(),
                .PRMWRDY = !psx.cdrom.parameter_fifo.is_full(),
                .RSLRRDY = !psx.cdrom.response_fifo.is_empty(),
                .DRQSTS = !psx.cdrom.data_fifo.is_empty() and psx.cdrom.data_requested,
                .BUSYSTS = psx.cdrom.pending_primary_command != null,
            };

            if (config.enable_cdrom_debug) {
                std.debug.print("Index/Status Load: {}\n", .{psx.mmio.cdrom.index_status});
            }

            return @bitCast(psx.mmio.cdrom.index_status);
        },
        MMIO.CommandPort1_Offset...MMIO.CommandPort3_Offset => {
            switch (psx.mmio.cdrom.index_status.index) {
                0 => {
                    const bank = &psx.mmio.cdrom.port.bank0.r;

                    switch (offset) {
                        MMIO.CommandPort1_Offset => @panic("Bank 0 Port 1"),
                        MMIO.CommandPort2_Offset => @panic("Bank 0 Port 2"),
                        MMIO.CommandPort3_Offset => {
                            const interrupt_enable_read = @TypeOf(bank.interrupt_enable){
                                .irq_enabled_mask = psx.cdrom.irq_enabled_mask,
                            };

                            if (config.enable_cdrom_debug) {
                                std.debug.print("Read interrupt enable register: {})\n", .{interrupt_enable_read});
                            }

                            return @bitCast(interrupt_enable_read);
                        },
                        else => unreachable,
                    }
                },
                1 => {
                    const bank = &psx.mmio.cdrom.port.bank1.r;

                    switch (offset) {
                        MMIO.CommandPort1_Offset => {
                            const response = psx.cdrom.response_fifo.pop() catch unreachable; // FIXME

                            if (config.enable_cdrom_debug) {
                                std.debug.print("Read response FIFO (got 0x{x})\n", .{response});
                            }
                            return response;
                        },
                        MMIO.CommandPort2_Offset => unreachable, // FIXME
                        MMIO.CommandPort3_Offset => {
                            const interrupt_flags = @TypeOf(bank.interrupt_flags){
                                .response_received = @enumFromInt(@as(u3, @truncate(psx.cdrom.irq_requested_mask))),
                                .command_start = 0, // FIXME related to SMEN
                            };

                            if (config.enable_cdrom_debug) {
                                std.debug.print("Read IRQ flag register: {}\n", .{interrupt_flags});
                            }

                            return @bitCast(interrupt_flags);
                        },
                        else => unreachable,
                    }
                },
                2 => {
                    const bank = &psx.mmio.cdrom.port.bank2.r;
                    _ = bank;
                    unreachable; // FIXME
                },
                3 => {
                    const bank = &psx.mmio.cdrom.port.bank3.r;
                    _ = bank;
                    unreachable; // FIXME
                },
            }
        },

        else => @panic("Invalid load offset"),
    }
}

// NOTE: Apparently for loading CDROM data fifo manually
pub fn load_mmio_u16(psx: *PSXState, offset: u29) u16 {
    std.debug.assert(offset >= MMIO.Offset and offset < MMIO.OffsetEnd);

    _ = psx;

    switch (offset) {
        MMIO.CommandPort2_Offset => {
            @panic("Implement me!"); // FIXME
        },
        else => @panic("Invalid CDROM MMIO offset"),
    }
}

pub fn store_mmio_u8(psx: *PSXState, offset: u29, value: u8) void {
    std.debug.assert(offset >= MMIO.Offset and offset < MMIO.OffsetEnd);

    if (config.enable_cdrom_debug) {
        std.debug.print("CDROM MMIO Store: offset=0x{x} bank={} value=0x{x} | ", .{ offset, psx.mmio.cdrom.index_status.index, value });
    }

    switch (offset) {
        MMIO.IndexStatus_Offset => {
            psx.mmio.cdrom.index_status.index = @truncate(value);

            if (config.enable_cdrom_debug) {
                std.debug.print("Set bank index: {}\n", .{psx.mmio.cdrom.index_status.index});
            }
        },
        MMIO.CommandPort1_Offset...MMIO.CommandPort3_Offset => {
            switch (psx.mmio.cdrom.index_status.index) {
                0 => {
                    const bank = &psx.mmio.cdrom.port.bank0.w;

                    switch (offset) {
                        MMIO.CommandPort1_Offset => {
                            const command: @TypeOf(bank.command) = @enumFromInt(value);
                            execution.queue_command(psx, command);
                        },
                        MMIO.CommandPort2_Offset => {
                            const parameter: @TypeOf(bank.parameter_fifo) = @bitCast(value);

                            if (config.enable_cdrom_debug) {
                                std.debug.print("CDROM wrote parameter: {}\n", .{parameter});
                            }

                            psx.cdrom.parameter_fifo.push(parameter) catch unreachable;
                        },
                        MMIO.CommandPort3_Offset => {
                            const request: @TypeOf(bank.request) = @bitCast(value);

                            std.debug.assert(request.zero_b0_4 == 0);

                            std.debug.assert(request.SMEN == 0);
                            std.debug.assert(request.BFWR == 0);

                            psx.cdrom.data_requested = request.BFRD;

                            if (config.enable_cdrom_debug) {
                                std.debug.print("BFRD Set: {}\n", .{request.BFRD});
                            }
                        },
                        else => unreachable,
                    }
                },
                1 => {
                    const bank = &psx.mmio.cdrom.port.bank1.w;

                    switch (offset) {
                        MMIO.CommandPort1_Offset => @panic("Bank 1 Port 1"),
                        MMIO.CommandPort2_Offset => {
                            const interrupt_enable_write: @TypeOf(bank.interrupt_enable) = @bitCast(value);

                            if (config.enable_cdrom_debug) {
                                std.debug.print("Interrupt enable value: {}\n", .{interrupt_enable_write});
                            }
                            std.debug.assert(interrupt_enable_write.zero == 0);

                            psx.cdrom.irq_enabled_mask = interrupt_enable_write.irq_enabled_mask;

                            execution.check_for_pending_interrupt_requests(psx);
                        },
                        MMIO.CommandPort3_Offset => {
                            const interrupt_flag_write: @TypeOf(bank.interrupt_flags) = @bitCast(value);

                            // FIXME unhandled
                            std.debug.assert(!interrupt_flag_write.SMADPCLR);
                            std.debug.assert(!interrupt_flag_write.CHPRST);

                            if (interrupt_flag_write.CLRPRM) {
                                psx.cdrom.parameter_fifo.discard();

                                if (config.enable_cdrom_debug) {
                                    std.debug.print("Reset Param FIFO\n", .{});
                                }
                            }

                            if (config.enable_cdrom_debug) {
                                std.debug.print("Interrupt ACK {}\n", .{interrupt_flag_write});
                            }

                            psx.cdrom.irq_requested_mask &= ~interrupt_flag_write.b0_4_ack;
                        },
                        else => unreachable,
                    }
                },
                2 => {
                    // const bank = &psx.mmio.cdrom.port.bank2.w;

                    switch (offset) {
                        MMIO.CommandPort1_Offset => @panic("Bank 2 Port 1"),
                        MMIO.CommandPort2_Offset => {
                            psx.cdrom.volume_cd_L_to_spu_L = @enumFromInt(value);

                            if (config.enable_cdrom_debug) {
                                std.debug.print("Set Volume CDROM L to SPU L = {}\n", .{psx.cdrom.volume_cd_L_to_spu_L});
                            }
                        },
                        MMIO.CommandPort3_Offset => {
                            psx.cdrom.volume_cd_L_to_spu_R = @enumFromInt(value);

                            if (config.enable_cdrom_debug) {
                                std.debug.print("Set Volume CDROM L to SPU R = {}\n", .{psx.cdrom.volume_cd_L_to_spu_R});
                            }
                        },
                        else => unreachable,
                    }
                },
                3 => {
                    const bank = &psx.mmio.cdrom.port.bank3.w;

                    switch (offset) {
                        MMIO.CommandPort1_Offset => {
                            psx.cdrom.volume_cd_R_to_spu_R = @enumFromInt(value);

                            if (config.enable_cdrom_debug) {
                                std.debug.print("Set Volume CDROM R to SPU R = {}\n", .{psx.cdrom.volume_cd_R_to_spu_R});
                            }
                        },
                        MMIO.CommandPort2_Offset => {
                            psx.cdrom.volume_cd_R_to_spu_L = @enumFromInt(value);

                            if (config.enable_cdrom_debug) {
                                std.debug.print("Set Volume CDROM R to SPU L = {}\n", .{psx.cdrom.volume_cd_R_to_spu_L});
                            }
                        },
                        MMIO.CommandPort3_Offset => {
                            const audio_volume_apply: @TypeOf(bank.audio_volume_apply) = @bitCast(value);

                            if (config.enable_cdrom_debug) {
                                std.debug.print("Audio Volume Apply Changes: {}\n", .{audio_volume_apply});
                            }

                            // FIXME
                            _ = audio_volume_apply.ADPMUTE;
                            _ = audio_volume_apply.CHNGATV;
                        },
                        else => unreachable,
                    }
                },
            }
        },
        else => @panic("Invalid store offset"),
    }
}

pub const MMIO = struct {
    pub const Offset = 0x1f801800;
    pub const OffsetEnd = Offset + SizeBytes;

    const IndexStatus_Offset = 0x1f801800;
    const CommandPort1_Offset = 0x1f801801;
    const CommandPort2_Offset = 0x1f801802;
    const CommandPort3_Offset = 0x1f801803;

    pub const Packed = MMIO_CDROM;

    const SizeBytes = mmio_gpu.MMIO.Offset - Offset;

    comptime {
        std.debug.assert(@sizeOf(Packed) == SizeBytes);
    }
};

const MMIO_CDROM = packed struct {
    index_status: packed struct(u8) { // 1F801800h - Index/Status Register (Bit0-1 R/W)
        index: u2 = undefined, // FIXME initial value 0-1 Index   Port 1F801801h-1F801803h index (0..3 = Index0..Index3)   (R/W)
        status: packed struct(u6) {
            // (Bit2-7 Read Only)
            ADPBUSY: bool, //   2   ADPBUSY XA-ADPCM fifo empty  (0=Empty) ;set when playing XA-ADPCM sound
            PRMEMPT: bool, //   3   PRMEMPT Parameter fifo empty (1=Empty) ;triggered before writing 1st byte
            PRMWRDY: bool, //   4   PRMWRDY Parameter fifo full  (0=Full)  ;triggered after writing 16 bytes
            RSLRRDY: bool, //   5   RSLRRDY Response fifo empty  (0=Empty) ;triggered after reading LAST byte
            DRQSTS: bool, //    6   DRQSTS  Data fifo empty      (0=Empty) ;triggered after reading LAST byte
            BUSYSTS: bool, //   7   BUSYSTS Command/parameter transmission busy  (1=Busy)
            // Bit3,4,5 are bound to 5bit counters; ie. the bits become true at specified amount of reads/writes, and thereafter once on every further 32 reads/writes.
        } = undefined, // FIXME initial value
    } = .{},

    // 1F801801h
    // 1F801802h
    // 1F801803h
    port: packed union {
        // 1F801802h.Index0..3 - Data Fifo - 8bit/16bit (R)
        // After ReadS/ReadN commands have generated INT1, software must set the Want Data bit (1F801803h.Index0.Bit7), then wait until Data Fifo becomes not empty (1F801800h.Bit6), the datablock (disk sector) can be then read from this register.
        //
        //   0-7  Data 8bit  (one byte), or alternately,
        //   0-15 Data 16bit (LSB=First byte, MSB=Second byte)
        //
        // The PSX hardware allows to read 800h-byte or 924h-byte sectors, indexed as [000h..7FFh] or [000h..923h], when trying to read further bytes, then the PSX will repeat the byte at index [800h-8] or [924h-4] as padding value.
        // Port 1F801802h can be accessed with 8bit or 16bit reads (ie. to read a 2048-byte sector, one can use 2048 load-byte opcodes, or 1024 load halfword opcodes, or, more conventionally, a 512 word DMA transfer; the actual CDROM databus is only 8bits wide, so CPU/DMA are apparently breaking 16bit/32bit reads into multiple 8bit reads from 1F801802h).
        bank0: packed union {
            r: packed struct(u24) {
                response_fifo_mirror: u8, // 1F801801h - Response Fifo Mirror (R)
                data_fifo_placeholder: u8, // 1F801802h.Index0 Data FIFO
                interrupt_enable: InterruptEnableR, // 1F801803h.Index0 - Interrupt Enable Register (R)
            },
            w: packed struct(u24) {
                // Writing to this address sends the command byte to the CDROM controller, which will then read-out any Parameter byte(s) which have been previously stored in the Parameter Fifo. It takes a while until the command/parameters are transferred to the controller, and until the response bytes are received; once when completed, interrupt INT3 is generated (or INT5 in case of invalid command/parameter values), and the response (or error code) can be then read from the Response Fifo. Some commands additionally have a second response, which is sent with another interrupt.
                command: Command, // 1F801801h.Index0 - Command Register (W)

                // Before sending a command, write any parameter byte(s) to this address.
                parameter_fifo: u8, // 1F801802h.Index0 - Parameter Fifo (W)

                request: packed struct(u8) { // 1F801803h.Index0 - Request Register (W)
                    zero_b0_4: u5, //   0-4 0    Not used (should be zero)
                    SMEN: u1, //   5   SMEN Want Command Start Interrupt on Next Command (0=No change, 1=Yes)
                    BFWR: u1, //   6   BFWR ...
                    BFRD: bool, //   7   BFRD Want Data         (0=No/Reset Data Fifo, 1=Yes/Load Data Fifo)
                },
            },
        },
        bank1: packed union {
            r: packed struct(u24) {
                // The response Fifo is a 16-byte buffer, most or all responses are less than 16 bytes, after reading the last used byte (or before reading anything when the response is 0-byte long), Bit5 of the Index/Status register becomes zero to indicate that the last byte was received.
                // When reading further bytes: The buffer is padded with 00h's to the end of the 16-bytes, and does then restart at the first response byte (that, without receiving a new response, so it'll always return the same 16 bytes, until a new command/response has been sent/received).
                response_fifo: u8, // 1F801801h.Index1 - Response Fifo (R)
                data_fifo_placeholder: u8, // 1F801802h.Index1 Data FIFO
                interrupt_flags: InterruptFlagsR, // 1F801803h.Index1 - Interrupt Flag Register (R/W)
            },
            w: packed struct(u24) {
                // This register seems to be restricted to 8bit bus, unknown if/how the PSX DMA controller can write to it (it might support only 16bit data for CDROM).
                sound_map_data_out: u8, // 1F801801h.Index1 - Sound Map Data Out (W)
                interrupt_enable: InterruptEnableW, // 1F801802h.Index1 - Interrupt Enable Register (W)
                interrupt_flags: InterruptFlagsW, // 1F801803h.Index1 - Interrupt Flag Register (R/W)
            },
        },
        bank2: packed union {
            r: packed struct(u24) {
                response_fifo_mirror: u8, // 1F801801h - Response Fifo Mirror (R)
                data_fifo_placeholder: u8, // 1F801802h.Index2 Data FIFO
                interrupt_enable_mirror: InterruptEnableR, // 1F801803h.Index2 - Interrupt Enable Register (R) (Mirror)
            },
            w: packed struct(u24) {
                sound_map_coding: packed struct { // 1F801801h.Index2 - Sound Map Coding Info (W)
                    channel: enum(u1) { //   0    Mono/Stereo     (0=Mono, 1=Stereo)
                        Mono,
                        Stereo,
                    },
                    unused_b1: u1, //   1    Reserved        (0)
                    sample_rate: enum(u1) { //   2    Sample Rate     (0=37800Hz, 1=18900Hz)
                        _37800Hz,
                        _18900Hz,
                    },
                    unused_b3: u1, //   3    Reserved        (0)
                    bits_per_sample: enum(u1) { //   4    Bits per Sample (0=4bit, 1=8bit)
                        _4bits,
                        _8bits,
                    },
                    unused_b5: u1, //   5    Reserved        (0)
                    enable_emphasis: bool, //   6    Emphasis        (0=Off, 1=Emphasis)
                    unused_b7: u1, //   7    Reserved        (0)
                },

                // Allows to configure the CD for mono/stereo output (eg. values "80h,0,80h,0" produce normal stereo volume, values "40h,40h,40h,40h" produce mono output of equivalent volume).
                // When using bigger values, the hardware does have some incomplete saturation support; the saturation works up to double volume (eg. overflows that occur on "FFh,0,FFh,0" or "80h,80h,80h,80h" are clipped to min/max levels), however, the saturation does NOT work properly when exceeding double volume (eg. mono with quad-volume "FFh,FFh,FFh,FFh").
                volume_cd_L_to_spu_L: Volume, // 1F801802h.Index2 - Audio Volume for Left-CD-Out to Left-SPU-Input (W)

                // Allows to configure the CD for mono/stereo output (eg. values "80h,0,80h,0" produce normal stereo volume, values "40h,40h,40h,40h" produce mono output of equivalent volume).
                // When using bigger values, the hardware does have some incomplete saturation support; the saturation works up to double volume (eg. overflows that occur on "FFh,0,FFh,0" or "80h,80h,80h,80h" are clipped to min/max levels), however, the saturation does NOT work properly when exceeding double volume (eg. mono with quad-volume "FFh,FFh,FFh,FFh").
                volume_cd_L_to_spu_R: Volume, // 1F801803h.Index2 - Audio Volume for Left-CD-Out to Right-SPU-Input (W)
            },
        },
        bank3: packed union {
            r: packed struct(u24) {
                response_fifo_mirror: u8, // 1F801801h - Response Fifo Mirror (R)
                data_fifo_placeholder: u8, // 1F801802h.Index3 Data FIFO
                interrupt_flags_mirror: InterruptFlagsR, // 1F801803h.Index3 - Interrupt Flag Register (R) (Mirror)
            },
            w: packed struct(u24) {
                // Allows to configure the CD for mono/stereo output (eg. values "80h,0,80h,0" produce normal stereo volume, values "40h,40h,40h,40h" produce mono output of equivalent volume).
                // When using bigger values, the hardware does have some incomplete saturation support; the saturation works up to double volume (eg. overflows that occur on "FFh,0,FFh,0" or "80h,80h,80h,80h" are clipped to min/max levels), however, the saturation does NOT work properly when exceeding double volume (eg. mono with quad-volume "FFh,FFh,FFh,FFh").
                //
                // After changing these registers, write 20h to 1F801803h.Index3.
                // Unknown if any existing games are actually supporting mono output. Resident Evil 2 uses these ports to produce fade-in/fade-out effects (although, for that purpose, it should be much easier to use Port 1F801DB0h).
                volume_cd_R_to_spu_R: Volume, // 1F801801h.Index3 - Audio Volume for Right-CD-Out to Right-SPU-Input (W)

                // Allows to configure the CD for mono/stereo output (eg. values "80h,0,80h,0" produce normal stereo volume, values "40h,40h,40h,40h" produce mono output of equivalent volume).
                // When using bigger values, the hardware does have some incomplete saturation support; the saturation works up to double volume (eg. overflows that occur on "FFh,0,FFh,0" or "80h,80h,80h,80h" are clipped to min/max levels), however, the saturation does NOT work properly when exceeding double volume (eg. mono with quad-volume "FFh,FFh,FFh,FFh").
                volume_cd_R_to_spu_L: Volume, // 1F801802h.Index3 - Audio Volume for Right-CD-Out to Left-SPU-Input (W)

                audio_volume_apply: packed struct { // 1F801803h.Index3 - Audio Volume Apply Changes (by writing bit5=1)
                    ADPMUTE: u1, // 0 Mute ADPCM (0=Normal, 1=Mute)
                    zero_b1_4: u4, // 1-4  Unused (should be zero)
                    CHNGATV: u1, // 5 Apply Audio Volume changes (0=No change, 1=Apply)
                    zero_b6_7: u2, //   6-7  Unused (should be zero)
                },
            },
        },
    } = undefined, // FIXME Initial value

    _unused: u96 = undefined,

    // Writing "1" bits to bit0-4 resets the corresponding IRQ flags; normally one should write 07h to reset the response bits, or 1Fh to reset all IRQ bits. Writing values like 01h is possible (eg. that would change INT3 to INT2, but doing that would be total nonsense). After acknowledge, the Response Fifo is made empty, and if there's been a pending command, then that command gets send to the controller.
    // The lower 3bit indicate the type of response received,
    //
    //   INT0   No response received (no interrupt request)
    //   INT1   Received SECOND (or further) response to ReadS/ReadN (and Play+Report)
    //   INT2   Received SECOND response (to various commands)
    //   INT3   Received FIRST response (to any command)
    //   INT4   DataEnd (when Play/Forward reaches end of disk) (maybe also for Read?)
    //   INT5   Received error-code (in FIRST or SECOND response)
    //          INT5 also occurs on SECOND GetID response, on unlicensed disks
    //          INT5 also occurs when opening the drive door (even if no command
    //             was sent, ie. even if no read-command or other command is active)
    //   INT6   N/A
    //   INT7   N/A
    //
    // The other 2bit indicate something else,
    //
    //   INT8   Unknown (never seen that bit set yet)
    //   INT10h Command Start (when INT10h requested via 1F801803h.Index0.Bit5)
    //
    // The response interrupts are queued, for example, if the 1st response is INT3, and the second INT5, then INT3 is delivered first, and INT5 is not delivered until INT3 is acknowledged (ie. the response interrupts are NOT ORed together to produce INT7 or so). The upper bits however can be ORed with the lower bits (ie. Command Start INT10h and 1st Response INT3 would give INT13h).
    // Caution - Unstable IRQ Flag polling
    // IRQ flag changes aren't synced with the MIPS CPU clock. If more than one bit gets set (and the CPU is reading at the same time) then the CPU does occassionally see only one of the newly bits:
    //
    //   0 ----------> 3   ;99.9%  normal case INT3's
    //   0 ----------> 5   ;99%    normal case INT5's
    //   0 ---> 1 ---> 3   ;0.1%   glitch: occurs about once per thousands of INT3's
    //   0 ---> 4 ---> 5   ;1%     glitch: occurs about once per hundreds of INT5's
    //
    // As workaround, do something like:
    //
    //  @@polling_lop:
    //   irq_flags = [1F801803h] AND 07h       ;<-- 1st read (may be still unstable)
    //   if irq_flags = 00h then goto @@polling_lop
    //   irq_flags = [1F801803h] AND 07h       ;<-- 2nd read (should be stable now)
    //   handle irq_flags and acknowledge them
    //
    // The problem applies only when manually polling the IRQ flags (an actual IRQ handler will get triggered when the flags get nonzero, and the flags will have stabilized once when the IRQ handler is reading them) (except, a combination of IRQ10h followed by IRQ3 can also have unstable LSBs within the IRQ handler).
    // The problem occurs only on older consoles (like LATE-PU-8), not on newer consoles (like PSone).
    const InterruptFlagsR = packed struct(u8) {
        response_received: IRQMask, //   0-2  Response Received
        unknown: u1 = 0, //   3    Unknown (usually 0)
        command_start: u1, //   4    Command Start
        always_ones: u3 = 0b111, //   5-7  Always 1 ;XXX "_"
    };
    const InterruptFlagsW = packed struct(u8) {
        //   0-2   Write: 7=Acknowledge   ;INT1..INT7
        //   3     Write: 1=Acknowledge   ;INT8  ;XXX CLRBFEMPT
        //   4     Write: 1=Acknowledge   ;INT10h;XXX CLRBFWRDY
        b0_4_ack: u5,
        SMADPCLR: bool, //   5     Write: 1=Unknown              ;XXX SMADPCLR
        CLRPRM: bool, //   6     Write: 1=Reset Parameter Fifo ;XXX CLRPRM
        CHPRST: bool, //   7     Write: 1=Unknown              ;XXX CHPRST
    };

    //   0-4  Interrupt Enable Bits (usually all set, ie. 1Fh=Enable All IRQs)
    //   5-7  Unknown/unused (write: should be zero) (read: usually all bits set)
    const InterruptEnableR = packed struct(u8) {
        irq_enabled_mask: u5,
        ones: u3 = 0b111,
    };
    const InterruptEnableW = packed struct(u8) {
        irq_enabled_mask: u5,
        zero: u3 = 0,
    };
};

pub const IRQMask = enum(u3) {
    None = 0,
    DataReady = 1,
    Complete = 2,
    ACK = 3,
    DataEnd = 4,
    Error = 5,
    _,
};

pub const Command = enum(u8) {
    //                   Command          Parameters      Response(s)
    Sync = 0x00, //      00h -            -               INT5(11h,40h)  ;reportedly "Sync" uh?
    Getstat = 0x01, //   01h Getstat      -               INT3(stat)
    Setloc = 0x02, //    02h Setloc     E amm,ass,asect   INT3(stat)
    Play = 0x03, //      03h Play       E (track)         INT3(stat), optional INT1(report bytes)
    Forward = 0x04, //   04h Forward    E -               INT3(stat), optional INT1(report bytes)
    Backward = 0x05, //  05h Backward   E -               INT3(stat), optional INT1(report bytes)
    ReadN = 0x06, //     06h ReadN      E -               INT3(stat), INT1(stat), datablock
    MotorOn = 0x07, //   07h MotorOn    E -               INT3(stat), INT2(stat)
    Stop = 0x08, //      08h Stop       E -               INT3(stat), INT2(stat)
    Pause = 0x09, //     09h Pause      E -               INT3(stat), INT2(stat)
    Init = 0x0A, //      0Ah Init         -               INT3(late-stat), INT2(stat)
    Mute = 0x0B, //      0Bh Mute       E -               INT3(stat)
    Demute = 0x0C, //    0Ch Demute     E -               INT3(stat)
    Setfilter = 0x0D, // 0Dh Setfilter  E file,channel    INT3(stat)
    Setmode = 0x0E, //   0Eh Setmode      mode            INT3(stat)
    Getparam = 0x0F, //  0Fh Getparam     -               INT3(stat,mode,null,file,channel)
    GetlocL = 0x10, //   10h GetlocL    E -               INT3(amm,ass,asect,mode,file,channel,sm,ci)
    GetlocP = 0x11, //   11h GetlocP    E -               INT3(track,index,mm,ss,sect,amm,ass,asect)
    SetSession = 0x12, //12h SetSession E session         INT3(stat), INT2(stat)
    GetTN = 0x13, //     13h GetTN      E -               INT3(stat,first,last)  ;BCD
    GetTD = 0x14, //     14h GetTD      E track (BCD)     INT3(stat,mm,ss)       ;BCD
    SeekL = 0x15, //     15h SeekL      E -               INT3(stat), INT2(stat)  ;\use prior Setloc
    SeekP = 0x16, //     16h SeekP      E -               INT3(stat), INT2(stat)  ;/to set target
    SetClock = 0x17, //  17h -            -               INT5(11h,40h)  ;reportedly "SetClock" uh?
    GetClock = 0x18, //  18h -            -               INT5(11h,40h)  ;reportedly "GetClock" uh?
    Test = 0x19, //      19h Test         sub_function    depends on sub_function (see below)
    GetID = 0x1A, //     1Ah GetID      E -               INT3(stat), INT2/5(stat,flg,typ,atip,"SCEx")
    ReadS = 0x1B, //     1Bh ReadS      E?-               INT3(stat), INT1(stat), datablock
    Reset = 0x1C, //     1Ch Reset        -               INT3(stat), Delay            ;-not DTL-H2000
    GetQ = 0x1D, //      1Dh GetQ       E adr,point       INT3(stat), INT2(10bytesSubQ,peak_lo) ;\not
    ReadTOC = 0x1E, //   1Eh ReadTOC      -               INT3(late-stat), INT2(stat)           ;/vC0
    VideoCD = 0x1F, //   1Fh VideoCD      sub,a,b,c,d,e   INT3(stat,a,b,c,d,e)   ;<-- SCPH-5903 only
    // 1Fh..4Fh -       -               INT5(11h,40h)  ;-Unused/invalid
    Secret1 = 0x50, //   50h Secret 1     -               INT5(11h,40h)  ;\
    Secret2 = 0x51, //   51h Secret 2     "Licensed by"   INT5(11h,40h)  ;
    Secret3 = 0x52, //   52h Secret 3     "Sony"          INT5(11h,40h)  ; Secret Unlock Commands
    Secret4 = 0x53, //   53h Secret 4     "Computer"      INT5(11h,40h)  ; (not in version vC0, and,
    Secret5 = 0x54, //   54h Secret 5     "Entertainment" INT5(11h,40h)  ; nonfunctional in japan)
    Secret6 = 0x55, //   55h Secret 6     "<region>"      INT5(11h,40h)  ;
    Secret7 = 0x56, //   56h Secret 7     -               INT5(11h,40h)  ;/
    SecretLock = 0x57, //57h SecretLock   -               INT5(11h,40h)  ;-Secret Lock Command
    Crash = 0x58, //     58h..5Fh Crash   -               Crashes the HC05 (jumps into a data area)
    //                   6Fh..FFh -       -               INT5(11h,40h)  ;-Unused/invalid
    _,
};

pub const TestSubCommand = enum(u8) {
    // 19h,20h --> INT3(yy,mm,dd,ver)
    // Indicates the date (Year-month-day, in BCD format) and version of the HC05 CDROM controller BIOS. Known/existing values are:
    //
    //   (unknown)        ;DTL-H2000 (with SPC700 instead HC05)
    //   94h,09h,19h,C0h  ;PSX (PU-7)               19 Sep 1994, version vC0 (a)
    //   94h,11h,18h,C0h  ;PSX (PU-7)               18 Nov 1994, version vC0 (b)
    //   94h,11h,28h,01h  ;PSX (DTL-H2000)          28 Nov 1994, version v01 (debug)
    //   95h,05h,16h,C1h  ;PSX (LATE-PU-8)          16 May 1995, version vC1 (a)
    //   95h,07h,24h,C1h  ;PSX (LATE-PU-8)          24 Jul 1995, version vC1 (b)
    //   95h,07h,24h,D1h  ;PSX (LATE-PU-8,debug ver)24 Jul 1995, version vD1 (debug)
    //   96h,08h,15h,C2h  ;PSX (PU-16, Video CD)    15 Aug 1996, version vC2 (VCD)
    //   96h,08h,18h,C1h  ;PSX (LATE-PU-8,yaroze)   18 Aug 1996, version vC1 (yaroze)
    //   96h,09h,12h,C2h  ;PSX (PU-18) (japan)      12 Sep 1996, version vC2 (a.jap)
    //   97h,01h,10h,C2h  ;PSX (PU-18) (us/eur)     10 Jan 1997, version vC2 (a)
    //   97h,08h,14h,C2h  ;PSX (PU-20)              14 Aug 1997, version vC2 (b)
    //   98h,06h,10h,C3h  ;PSX (PU-22)              10 Jun 1998, version vC3 (a)
    //   99h,02h,01h,C3h  ;PSX/PSone (PU-23, PM-41) 01 Feb 1999, version vC3 (b)
    //   A1h,03h,06h,C3h  ;PSone/late (PM-41(2))    06 Jun 2001, version vC3 (c)
    //   (unknown)        ;PS2,   xx xxx xxxx, late PS2 models...?
    GetDateBCD = 0x20,

    // 19h,21h --> INT3(flags)
    // Returns the current status of the POS0 and DOOR switches.
    //
    //   Bit0   = HeadIsAtPos0 (0=No, 1=Pos0)
    //   Bit1   = DoorIsOpen   (0=No, 1=Open)
    //   Bit2   = EjectButtonOrOutSwOrSo? (DTL-H2000 only) (always 0 on retail)
    //   Bit3-7 = AlwaysZero
    //
    //
    // 19h,22h --> INT3("for Europe")
    //
    //   Caution: Supported only in BIOS version vC1 and up. Not supported in vC0.
    //
    // Indicates the region that console is to be used in:
    //
    //   INT5(11h,10h)      --> NTSC, Japan (vC0)         --> requires "SCEI" discs
    //   INT3("for Europe") --> PAL, Europe               --> requires "SCEE" discs
    //   INT3("for U/C")    --> NTSC, North America       --> requires "SCEA" discs
    //   INT3("for Japan")  --> NTSC, Japan / NTSC, Asia  --> requires "SCEI" discs
    //   INT3("for NETNA")  --> Region-free yaroze version--> requires "SCEx" discs
    //   INT3("for US/AEP") --> Region-free debug version --> accepts unlicensed CDRs
    //
    // The CDROMs must contain a matching SCEx string accordingly.
    // The string "for Europe" does also suggest 50Hz PAL/SECAM video hardware.
    // The Yaroze accepts any normal SCEE,SCEA,SCEI discs, plus special SCEW discs.
    //
    // 19h,23h --> INT3("CXD2940Q/CXD1817Q/CXD2545Q/CXD1782BR") ;Servo Amplifier
    // 19h,24h --> INT3("CXD2940Q/CXD1817Q/CXD2545Q/CXD2510Q") ;Signal Processor
    // 19h,25h --> INT3("CXD2940Q/CXD1817Q/CXD1815Q/CXD1199BQ") ;Decoder/FIFO
    //
    //   Caution: Supported only in BIOS version vC1 and up. Not supported in vC0.
    //
    // Indicates the chipset that the CDROM controller is intended to be used with. The strings aren't always precisely correct (CXD1782BR is actually CXA1782BR, ie. CXA, not CXD) (and CXD1199BQ chips exist on PU-7 boards, but later PU-8 boards do actually use CXD1815Q) (and CXD1817Q is actually CXD1817R) (and newer PSones are using CXD2938Q or possibly CXD2941R chips, but nothing called CXD2940Q).
    // Note: Yaroze responds by CXD1815BQ instead of CXD1199BQ (but not by CXD1815Q).
    //
    // 19h,04h --> INT3(stat) ;Read SCEx string (and force motor on)
    // Resets the total/success counters to zero, and does then try to read the SCEx string from the current location (the SCEx is stored only in the Lead-In area, so, if the drive head is elsewhere, it will usually not find any strings, unless a modchip is permanently simulating SCEx strings).
    // This is a raw test command (the successful or unsuccessful results do not lock/unlock the disk). The results can be read with command 19h,05h (which will terminate the SCEx reading), or they can be read from RAM with command 19h,60h,lo,hi (which doesn't stop reading). Wait 1-2 seconds before expecting any results.
    // Note: Like 19h,00h, this command forces the drive motor to spin at standard speed (synchronized with the data on the disk), works even if the shell is open (but stops spinning after a while if the drive is empty).
    //
    // 19h,05h --> INT3(total,success) ;Get SCEx Counters
    // Returns the total number of "Sxxx" strings received (where at least the first byte did match), and the number of full "SCEx" strings (where all bytes did match). Typically, the values are "01h,01h" for Licensed PSX Data CDs, or "00h,00h" for disk missing, unlicensed data CDs, Audio CDs.
    // The counters are reset to zero, and SCEx receive mode is active for a few seconds after booting a new disk (on power up, on closing the drive door, on sending a Reset command, and on sub_function 04h). The disk is unlocked if the "success" counter is nonzero, the only exception is sub_function 04h which does update the counters, but does not lock/unlock the disk.
    _,
};

//   0-7  Volume Level (00h..FFh) (00h=Off, FFh=Max/Double, 80h=Default/Normal)
pub const Volume = enum(u8) {
    Off = 0,
    Normal = 0x80,
    Max = 0xff,
    _,
};
