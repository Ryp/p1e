const std = @import("std");

const PSXState = @import("../state.zig").PSXState;

const config = @import("../config.zig");
const cpu_execution = @import("../cpu/execution.zig");
const timings = @import("../timings.zig");

const mmio = @import("mmio.zig");
const image = @import("image.zig");

pub fn queue_command(psx: *PSXState, command: mmio.Command) void {
    if (config.enable_cdrom_debug) {
        std.debug.print("CDROM Queue command: {}\n", .{command});
    }

    std.debug.assert(psx.cdrom.pending_primary_command == null);
    std.debug.assert(psx.cdrom.pending_secondary_command == null or psx.cdrom.pending_secondary_command.?.command == .ReadN);

    psx.cdrom.pending_primary_command = .{
        .command = command,
        .ticks_remaining = get_command_process_ticks(),
    };
}

pub fn execute_primary_command(psx: *PSXState, command: mmio.Command) void {
    if (config.enable_cdrom_debug) {
        std.debug.print("CDROM Execute primary command: {}\n", .{command});
    }

    // FIXME This assert will probably break soon
    std.debug.assert(psx.cdrom.pending_secondary_command == null or psx.cdrom.pending_secondary_command.?.command == .ReadN);

    switch (command) {
        .Sync => unreachable,
        .Getstat => {
            request_interrupt_and_push_stat(psx, .ACK);

            if (config.enable_cdrom_debug) {
                std.debug.print("stat: {}\n", .{psx.cdrom.stat});
            }
        },
        .Setloc => {
            const minute_bcd = psx.cdrom.parameter_fifo.pop() catch unreachable;
            const second_bcd = psx.cdrom.parameter_fifo.pop() catch unreachable;
            const frame_bcd = psx.cdrom.parameter_fifo.pop() catch unreachable;

            const sector_index = image.msf_bcd_to_sector_index(@bitCast(minute_bcd), @bitCast(second_bcd), @bitCast(frame_bcd)) catch {
                std.debug.print("Invalid MSF in Setloc: {x}:{x}:{x}\n", .{ minute_bcd, second_bcd, frame_bcd });

                request_interrupt_and_push_stat(psx, .Error);
                return;
            };

            request_interrupt_and_push_stat(psx, .ACK);

            psx.cdrom.seek_target_sector = sector_index;

            if (config.enable_cdrom_debug) {
                std.debug.print("Setloc: {}\n", .{psx.cdrom.seek_target_sector.?});
            }
        },
        .Play => unreachable,
        .Forward => unreachable,
        .Backward => unreachable,
        .ReadN => {
            std.debug.assert(!psx.cdrom.stat.is_shell_open);
            std.debug.assert(psx.cdrom.stat.main_state == .Idle or psx.cdrom.stat.main_state == .Seeking);
            std.debug.assert(psx.cdrom.seek_target_sector != null); // Technically supported, might break later
            std.debug.assert(psx.cdrom.image != null);

            request_interrupt_and_push_stat(psx, .ACK);

            psx.cdrom.stat.main_state = .Reading;

            psx.cdrom.pending_secondary_command = .{
                .command = .ReadN,
                .ticks_remaining = get_readn_ticks(psx),
            };
        },
        .MotorOn => unreachable,
        .Stop => unreachable,
        .Pause => {
            request_interrupt_and_push_stat(psx, .ACK);

            psx.cdrom.stat.main_state = .Idle; // Order of this matters since we send stat first
            psx.cdrom.seek_target_sector = null;

            psx.cdrom.pending_secondary_command = .{
                .command = .Pause,
                .ticks_remaining = PauseDurationTicks,
            };
        },
        .Init => {
            // Reset stuff
            psx.cdrom.parameter_fifo.discard();
            psx.cdrom.response_fifo.discard();
            psx.cdrom.data_fifo.discard();
            psx.cdrom.seek_target_sector = null;

            request_interrupt_and_push_stat(psx, .ACK);

            // Start motor
            psx.cdrom.stat.is_spindle_motor_on = true;

            psx.cdrom.pending_secondary_command = .{
                .command = .Init,
                .ticks_remaining = InitDurationTicks,
            };
        },
        .Mute => unreachable,
        .Demute => {
            if (config.enable_cdrom_debug) {
                std.debug.print("CDROM Demute command received, but unimplemented\n", .{});
            }

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
                sector_slice_mode: SectorSliceMode, // 5   Sector Size (0=800h=DataOnly, 1=924h=WholeSectorExceptSyncBytes)
                xa_adpcm: u1, // 6   XA-ADPCM    (0=Off, 1=Send XA-ADPCM sectors to SPU Audio Input)
                speed: enum(u1) { // 7   Speed       (0=Normal speed, 1=Double speed)
                    Normal,
                    Double,
                },
            };

            const mode: SetMode = @bitCast(psx.cdrom.parameter_fifo.pop() catch unreachable);

            if (config.enable_cdrom_debug) {
                std.debug.print("Setmode: {}\n", .{mode});
            }

            std.debug.assert(0 == mode.cdda);
            std.debug.assert(0 == mode.auto_pause);
            std.debug.assert(0 == mode.enable_report_interrupts);
            std.debug.assert(0 == mode.xa_filter);
            std.debug.assert(0 == mode.ignore_bit);
            std.debug.assert(0 == mode.xa_adpcm);

            psx.cdrom.read_speed_multiplier = switch (mode.speed) {
                .Normal => 1,
                .Double => 2,
            };

            psx.cdrom.sector_slice_mode = mode.sector_slice_mode;

            request_interrupt_and_push_stat(psx, .ACK);
        },
        .Getparam => unreachable,
        .GetlocL => unreachable,
        .GetlocP => unreachable,
        .SetSession => unreachable,
        .GetTN => unreachable,
        .GetTD => unreachable,
        .SeekL => {
            std.debug.assert(!psx.cdrom.stat.is_shell_open);
            std.debug.assert(psx.cdrom.stat.main_state == .Idle);
            std.debug.assert(psx.cdrom.seek_target_sector != null);
            std.debug.assert(psx.cdrom.image != null);

            if (config.enable_cdrom_debug) {
                std.debug.print("SeekL to LBA {}\n", .{psx.cdrom.seek_target_sector.?});
            }

            request_interrupt_and_push_stat(psx, .ACK);

            psx.cdrom.stat.main_state = .Seeking;

            psx.cdrom.pending_secondary_command = .{
                .command = .SeekL,
                .ticks_remaining = SeekLDurationTicks,
            };
        },
        .SeekP => unreachable,
        .SetClock => unreachable,
        .GetClock => unreachable,
        .Test => {
            const sub_command: mmio.TestSubCommand = @enumFromInt(psx.cdrom.parameter_fifo.pop() catch unreachable);

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
        .GetID => {
            request_interrupt_and_push_stat(psx, .ACK);

            psx.cdrom.pending_secondary_command = .{
                .command = .GetID,
                .ticks_remaining = GetIDDurationTicks,
            };
        },
        .ReadS => unreachable,
        .Reset => unreachable,
        .GetQ => unreachable,
        .ReadTOC => {
            request_interrupt_and_push_stat(psx, .ACK);

            psx.cdrom.pending_secondary_command = .{
                .command = .ReadTOC,
                .ticks_remaining = ReadTOCDurationTicks,
            };
        },
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
    // FIXME A better state machine would be nice
    if (psx.cdrom.pending_primary_command) |*pending_command| {
        pending_command.ticks_remaining -|= ticks;

        if (pending_command.ticks_remaining == 0) {
            execute_primary_command(psx, pending_command.command);

            psx.cdrom.pending_primary_command = null;
        }
    }

    // FIXME A better state machine would be nice
    if (psx.cdrom.pending_secondary_command) |*pending_command| {
        pending_command.ticks_remaining -|= ticks;

        if (pending_command.ticks_remaining == 0) {
            const command = pending_command.command;

            if (config.enable_cdrom_debug) {
                std.debug.print("CDROM Execute secondary command: {}\n", .{command});
            }

            switch (command) {
                .ReadN => {
                    std.debug.assert(psx.cdrom.stat.main_state == .Reading);
                    std.debug.assert(psx.cdrom.seek_target_sector != null);
                    std.debug.assert(psx.cdrom.image != null);

                    // LeadInSectors is removed because BIN/CUE images don't contain them
                    const bin_sector_index = psx.cdrom.seek_target_sector.? - image.LeadInSectors;
                    const raw_sector = psx.cdrom.image.?.sectors[bin_sector_index];

                    // Copy full raw sector into data fifo
                    @memcpy(&psx.cdrom.data_fifo.buffer, std.mem.asBytes(&raw_sector));

                    const fifo = &psx.cdrom.data_fifo;

                    // Patch read/write indices to reflect new data for the next FIFO pop()
                    fifo.head, fifo.count = switch (psx.cdrom.sector_slice_mode) {
                        .Mode2_Form1_Data_0x800 => .{ 24, 0x800 },
                        .WholeSectorExceptSyncBytes_0x924 => .{ 12, 0x924 },
                    };
                    fifo.tail = fifo.head + fifo.count;

                    // Advance to next sector
                    psx.cdrom.seek_target_sector.? += 1;

                    request_interrupt_and_push_stat(psx, .DataReady);

                    // Keep command going but reset timer
                    pending_command.ticks_remaining = get_readn_ticks(psx);
                },
                .Pause => {
                    request_interrupt_and_push_stat(psx, .Complete);
                    psx.cdrom.pending_secondary_command = null;
                },
                .Init => {
                    request_interrupt_and_push_stat(psx, .Complete);
                    psx.cdrom.pending_secondary_command = null;
                },
                .SeekL => {
                    request_interrupt_and_push_stat(psx, .Complete);
                    psx.cdrom.pending_secondary_command = null;
                },
                .GetID => {
                    //   1st byte: stat  (as usually, but with bit3 same as bit7 in 2nd byte)
                    request_interrupt_and_push_stat(psx, .Complete);

                    psx.cdrom.response_fifo.push(@bitCast(IDFlagByte{
                        .cd_type = .Data, // FIXME Detect that?
                        .cd_status = if (psx.cdrom.image == null) .Missing else .Present,
                        .has_id_error = psx.cdrom.stat.has_id_error,
                    })) catch unreachable;

                    if (psx.cdrom.image != null) {
                        //   3rd byte: Disk type (from TOC Point=A0h) (eg. 00h=Audio or Mode1, 20h=Mode2)
                        psx.cdrom.response_fifo.push(0x20) catch unreachable; // FIXME

                        //   4th byte: Usually 00h (or 8bit ATIP from Point=C0h, if session info exists)
                        //     that 8bit ATIP value is taken form the middle 8bit of the 24bit ATIP value
                        psx.cdrom.response_fifo.push(0x00) catch unreachable; // FIXME

                        // FIXME Make it match with the PSX BIOS automatically
                        psx.cdrom.response_fifo.push('S') catch unreachable;
                        psx.cdrom.response_fifo.push('C') catch unreachable;
                        psx.cdrom.response_fifo.push('E') catch unreachable;
                        psx.cdrom.response_fifo.push('A') catch unreachable;
                    } else {
                        for (0..6) |_| {
                            psx.cdrom.response_fifo.push(0x00) catch unreachable;
                        }
                    }

                    psx.cdrom.pending_secondary_command = null;
                },
                .ReadTOC => {
                    request_interrupt_and_push_stat(psx, .Complete);

                    // FIXME do nothing!

                    psx.cdrom.pending_secondary_command = null;
                },
                else => @panic("CDROM timed command not implemented"),
            }
        }
    }
}

fn request_interrupt(psx: *PSXState, irq_mask: mmio.IRQMask) void {
    psx.cdrom.irq_requested_mask = @intFromEnum(irq_mask); // Weird behavior of int in a mask encoding...

    check_for_pending_interrupt_requests(psx);
}

fn request_interrupt_and_push_stat(psx: *PSXState, irq_mask: mmio.IRQMask) void {
    request_interrupt(psx, irq_mask);

    std.debug.assert(psx.cdrom.response_fifo.is_empty());
    psx.cdrom.response_fifo.push(@bitCast(psx.cdrom.stat)) catch unreachable;
}

pub fn check_for_pending_interrupt_requests(psx: *PSXState) void {
    const pending_mask: u5 = psx.cdrom.irq_requested_mask & psx.cdrom.irq_enabled_mask;

    if (pending_mask != 0) {
        cpu_execution.request_hardware_interrupt(psx, .IRQ2_CDRom);

        if (config.enable_cdrom_debug) {
            std.debug.print("CDROM Interrupt requested with mask: {}\n", .{@as(mmio.IRQMask, @enumFromInt(pending_mask))});
        }
    }
}

pub fn load_data_u32(psx: *PSXState) u32 {
    if (psx.cdrom.data_requested) {
        std.debug.assert(psx.cdrom.data_fifo.count >= 4);

        // NOTE: This FIFO never wraps around
        const value = std.mem.readInt(u32, psx.cdrom.data_fifo.buffer[psx.cdrom.data_fifo.head..][0..4], .little);

        // Update FIFO state manually
        psx.cdrom.data_fifo.head += 4;
        psx.cdrom.data_fifo.count -= 4;

        return value;
    } else {
        return 0;
    }
}

// NOTE: All of this is very rough
const InitDurationTicks = 5000;
const SeekLDurationTicks = 5000;
const PauseDurationTicks = 20000;
const GetIDDurationTicks = 5000;
const ReadTOCDurationTicks = 500000;

fn get_readn_ticks(psx: *PSXState) u32 {
    return timings.TicksPerSeconds / (image.FramesPerSeconds * psx.cdrom.read_speed_multiplier);
}

// See GetAckDelayForCommand in duckstation
fn get_command_process_ticks() u32 {
    return 20_000;
}

pub const SectorSliceMode = enum(u1) {
    Mode2_Form1_Data_0x800,
    WholeSectorExceptSyncBytes_0x924,
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

const IDFlagByte = packed struct(u8) {
    unknown_b0: u1 = 0,
    unknown_b1: u1 = 0,
    unknown_b2: u1 = 0,
    unknown_b3: u1 = 0,
    cd_type: enum(u1) {
        Data = 0,
        Audio = 1,
    },
    unknown_b5: u1 = 0,
    cd_status: enum(u1) {
        Present = 0,
        Missing = 1,
    },
    has_id_error: bool,
};
