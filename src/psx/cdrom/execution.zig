const std = @import("std");

const PSXState = @import("../state.zig").PSXState;

const config = @import("../config.zig");
const cpu_execution = @import("../cpu/execution.zig");

pub fn execute_command(psx: *PSXState, command_byte: u8) void {
    const command: Command = @enumFromInt(command_byte);

    if (config.enable_cdrom_debug) {
        std.debug.print("CDROM Execute command: {}\n", .{command});
    }

    std.debug.assert(psx.cdrom.active_timed_command == null);

    switch (command) {
        .Sync => unreachable,
        .Getstat => {
            if (config.enable_cdrom_debug) {
                std.debug.print("stat: {}\n", .{psx.cdrom.stat});
            }

            request_interrupt_and_push_stat(psx, .ACK);
        },
        .Setloc => {
            const BCD_Byte = packed struct(u8) {
                lo: u4,
                hi: u4,
            };

            const minute_bcd: BCD_Byte = @bitCast(psx.cdrom.parameter_fifo.pop() catch unreachable);
            const second_bcd: BCD_Byte = @bitCast(psx.cdrom.parameter_fifo.pop() catch unreachable);
            const frame_bcd: BCD_Byte = @bitCast(psx.cdrom.parameter_fifo.pop() catch unreachable);

            std.debug.assert(minute_bcd.hi < 10 and minute_bcd.lo < 10);
            std.debug.assert(second_bcd.hi < 6 and second_bcd.lo < 10);
            std.debug.assert(frame_bcd.hi < 10 and frame_bcd.lo < 10);

            const minute = @as(u8, minute_bcd.hi) * 10 + minute_bcd.lo;
            const second = @as(u8, second_bcd.hi) * 10 + second_bcd.lo;
            const frame = @as(u8, frame_bcd.hi) * 10 + frame_bcd.lo;

            std.debug.assert(frame < 75);

            psx.cdrom.seek_target = .{
                .minute = minute,
                .second = second,
                .frame = frame,
            };

            std.debug.print("Setloc: {}\n", .{psx.cdrom.seek_target.?});

            request_interrupt_and_push_stat(psx, .ACK);
        },
        .Play => unreachable,
        .Forward => unreachable,
        .Backward => unreachable,
        .ReadN => {
            psx.cdrom.stat.main_state = .Reading; // FIXME

            request_interrupt_and_push_stat(psx, .ACK);

            const readn_ticks = 5000; // FIXME
            psx.cdrom.active_timed_command = .{ .command = .ReadN, .ticks_remaining = readn_ticks };

            std.debug.print("CDROM ReadN command received, but incomplete!\n", .{});
        },
        .MotorOn => unreachable,
        .Stop => unreachable,
        .Pause => unreachable,
        .Init => {
            // Reset stuff
            psx.cdrom.parameter_fifo.discard();
            psx.cdrom.response_fifo.discard();
            psx.cdrom.seek_target = null;

            // Start motor
            psx.cdrom.stat.is_spindle_motor_on = true;

            request_interrupt_and_push_stat(psx, .ACK);

            const init_ticks = 5000; // FIXME
            psx.cdrom.active_timed_command = .{ .command = .Init, .ticks_remaining = init_ticks };
        },
        .Mute => unreachable,
        .Demute => {
            std.debug.print("CDROM Demute command received, but unimplemented\n", .{});
            request_interrupt_and_push_stat(psx, .ACK);
        },
        .Setfilter => unreachable,
        .Setmode => {
            const SetMode = packed struct(u8) {
                cdda: u1, // 0   CDDA        (0=Off, 1=Allow to Read CD-DA Sectors; ignore missing EDC)
                auto_pause: u1, // 1   AutoPause   (0=Off, 1=Auto Pause upon End of Track) ;for Audio Play
                enable_report_interrupts: u1, // 2   Report      (0=Off, 1=Enable Report-Interrupts for Audio Play)
                xa_filter: u1, // 3   XA-Filter   (0=Off, 1=Process only XA-ADPCM sectors that match Setfilter)
                ignore_bit: u1, // 4   Ignore Bit  (0=Normal, 1=Ignore Sector Size and Setloc position)
                sector_size: enum(u1) { // 5   Sector Size (0=800h=DataOnly, 1=924h=WholeSectorExceptSyncBytes)
                    DataOnly,
                    WholeSectorExceptSyncBytes,
                },
                xa_adpcm: u1, // 6   XA-ADPCM    (0=Off, 1=Send XA-ADPCM sectors to SPU Audio Input)
                speed: enum(u1) { // 7   Speed       (0=Normal speed, 1=Double speed)
                    Normal,
                    Double,
                },
            };

            const mode: SetMode = @bitCast(psx.cdrom.parameter_fifo.pop() catch unreachable);
            std.debug.print("{} Setmode: {}\n", .{ psx.step_index, mode });

            // FIXME
            std.debug.assert(0 == mode.cdda);
            std.debug.assert(0 == mode.auto_pause);
            std.debug.assert(0 == mode.enable_report_interrupts);
            std.debug.assert(0 == mode.xa_filter);
            std.debug.assert(0 == mode.ignore_bit);
            // std.debug.assert(!mode.sector_size);
            std.debug.assert(0 == mode.xa_adpcm);
            // std.debug.assert(!mode.speed);

            request_interrupt_and_push_stat(psx, .ACK);

            std.debug.print("CDROM Setmode command received, but unimplemented\n", .{});
        },
        .Getparam => unreachable,
        .GetlocL => unreachable,
        .GetlocP => unreachable,
        .SetSession => unreachable,
        .GetTN => unreachable,
        .GetTD => unreachable,
        .SeekL => unreachable,
        .SeekP => unreachable,
        .SetClock => unreachable,
        .GetClock => unreachable,
        .Test => {
            const sub_command: TestSubCommand = @enumFromInt(psx.cdrom.parameter_fifo.pop() catch unreachable);

            if (config.enable_cdrom_debug) {
                std.debug.print("CDROM Test command: {}\n", .{sub_command});
            }

            switch (sub_command) {
                .GetDateBCD => {
                    const bios_version = HC05ControllerBiosVersionBCD_PU7;
                    psx.cdrom.response_fifo.push(bios_version.year) catch unreachable;
                    psx.cdrom.response_fifo.push(bios_version.month) catch unreachable;
                    psx.cdrom.response_fifo.push(bios_version.day) catch unreachable;
                    psx.cdrom.response_fifo.push(bios_version.version) catch unreachable;

                    request_interrupt(psx, .ACK);
                },
                else => @panic("Unknown CDROM Test command"),
            }
        },
        .GetID => unreachable,
        .ReadS => unreachable,
        .Reset => unreachable,
        .GetQ => unreachable,
        .ReadTOC => unreachable,
        .VideoCD => unreachable,
        .Secret1 => unreachable,
        .Secret2 => unreachable,
        .Secret3 => unreachable,
        .Secret4 => unreachable,
        .Secret5 => unreachable,
        .Secret6 => unreachable,
        .Secret7 => unreachable,
        .SecretLock => unreachable,
        .Crash => unreachable,
        else => @panic("Invalid CDROM command"),
    }
}

pub fn execute_ticks(psx: *PSXState, ticks: u32) void {
    if (psx.cdrom.active_timed_command) |*timed_command| {
        timed_command.ticks_remaining -|= ticks;

        if (timed_command.ticks_remaining == 0) {
            const command = timed_command.command;
            if (config.enable_cdrom_debug) {

        std.debug.print("CDROM Execute timed command: {}\n", .{command});
    }

    switch (command) {
        .Init => {
            request_interrupt_and_push_stat(psx, .Complete);
            psx.cdrom.active_timed_command = null;
        },
        .ReadN => {
            // FIXME put data in!
            request_interrupt_and_push_stat(psx, .DataReady);
            @panic("");
        },
        else => @panic("CDROM timed command not implemented"),
    }
        }
    }
}

fn request_interrupt(psx: *PSXState, irq_mask: IRQMask) void {
    psx.cdrom.irq_requested_mask = @intFromEnum(irq_mask); // Weird behavior of int in a mask encoding...

    if (psx.cdrom.irq_requested_mask & psx.cdrom.irq_enabled_mask != 0) {
        cpu_execution.request_hardware_interrupt(psx, .IRQ2_CDRom);

        if (config.enable_cdrom_debug) {
            std.debug.print("CDROM interrupt requested with {}!\n", .{irq_mask});
        }
    }
}

fn request_interrupt_and_push_stat(psx: *PSXState, irq_mask: IRQMask) void {
    request_interrupt(psx, irq_mask);

    std.debug.assert(psx.cdrom.response_fifo.is_empty());
    psx.cdrom.response_fifo.push(@bitCast(psx.cdrom.stat)) catch unreachable;
}

const IRQMask = enum(u5) {
    DataReady = 1,
    Complete = 2,
    ACK = 3,
    DataEnd = 4,
    Error = 5,
};

//  (unknown)        ;DTL-H2000 (with SPC700 instead HC05)
//  94h,09h,19h,C0h  ;PSX (PU-7)               19 Sep 1994, version vC0 (a)
//  94h,11h,18h,C0h  ;PSX (PU-7)               18 Nov 1994, version vC0 (b)
//  94h,11h,28h,01h  ;PSX (DTL-H2000)          28 Nov 1994, version v01 (debug)
//  95h,05h,16h,C1h  ;PSX (LATE-PU-8)          16 May 1995, version vC1 (a)
//  95h,07h,24h,C1h  ;PSX (LATE-PU-8)          24 Jul 1995, version vC1 (b)
//  95h,07h,24h,D1h  ;PSX (LATE-PU-8,debug ver)24 Jul 1995, version vD1 (debug)
//  96h,08h,15h,C2h  ;PSX (PU-16, Video CD)    15 Aug 1996, version vC2 (VCD)
//  96h,08h,18h,C1h  ;PSX (LATE-PU-8,yaroze)   18 Aug 1996, version vC1 (yaroze)
//  96h,09h,12h,C2h  ;PSX (PU-18) (japan)      12 Sep 1996, version vC2 (a.jap)
//  97h,01h,10h,C2h  ;PSX (PU-18) (us/eur)     10 Jan 1997, version vC2 (a)
//  97h,08h,14h,C2h  ;PSX (PU-20)              14 Aug 1997, version vC2 (b)
//  98h,06h,10h,C3h  ;PSX (PU-22)              10 Jun 1998, version vC3 (a)
//  99h,02h,01h,C3h  ;PSX/PSone (PU-23, PM-41) 01 Feb 1999, version vC3 (b)
//  A1h,03h,06h,C3h  ;PSone/late (PM-41(2))    06 Jun 2001, version vC3 (c)
//  (unknown)        ;PS2,   xx xxx xxxx, late PS2 models...?
const HC05ControllerBiosVersionBCD = packed struct {
    year: u8, // BCD
    month: u8, // BCD
    day: u8, // BCD
    version: u8, // BCD
};

const HC05ControllerBiosVersionBCD_PU7 = HC05ControllerBiosVersionBCD{
    .year = 0x94,
    .month = 0x09,
    .day = 0x19,
    .version = 0xC0,
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

const TestSubCommand = enum(u8) {
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
