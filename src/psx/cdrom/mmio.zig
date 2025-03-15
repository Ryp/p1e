const std = @import("std");

const PSXState = @import("../state.zig").PSXState;
const mmio = @import("../mmio.zig");
const mmio_gpu = @import("../gpu/mmio.zig");

pub fn load_mmio_generic(comptime T: type, psx: *PSXState, offset: u29) T {
    std.debug.assert(offset < MMIO.OffsetEnd);
    std.debug.assert(offset >= MMIO.Offset);

    const type_slice = mmio.get_mutable_mmio_slice_generic(u32, psx, offset);
    _ = type_slice;

    switch (offset) {
        else => unreachable,
    }
}

pub fn store_mmio_generic(comptime T: type, psx: *PSXState, offset: u29, value: T) void {
    std.debug.assert(offset >= MMIO.Offset);
    std.debug.assert(offset < MMIO.OffsetEnd);

    _ = psx;
    _ = value;

    switch (offset) {
        else => unreachable,
    }
}

pub const MMIO = struct {
    pub const Offset = 0x1f801800;
    pub const OffsetEnd = Offset + SizeBytes;

    const IndexStatus_Offset = 0x1f801800;

    pub const Packed = MMIO_CDROM;

    const SizeBytes = mmio_gpu.MMIO.Offset - Offset;

    comptime {
        std.debug.assert(@sizeOf(Packed) == SizeBytes);
    }
};

const MMIO_CDROM = packed struct {
    // 1F801800h - Index/Status Register (Bit0-1 R/W) (Bit2-7 Read Only)
    //
    //   0-1 Index   Port 1F801801h-1F801803h index (0..3 = Index0..Index3)   (R/W)
    //   2   ADPBUSY XA-ADPCM fifo empty  (0=Empty) ;set when playing XA-ADPCM sound
    //   3   PRMEMPT Parameter fifo empty (1=Empty) ;triggered before writing 1st byte
    //   4   PRMWRDY Parameter fifo full  (0=Full)  ;triggered after writing 16 bytes
    //   5   RSLRRDY Response fifo empty  (0=Empty) ;triggered after reading LAST byte
    //   6   DRQSTS  Data fifo empty      (0=Empty) ;triggered after reading LAST byte
    //   7   BUSYSTS Command/parameter transmission busy  (1=Busy)
    //
    // Bit3,4,5 are bound to 5bit counters; ie. the bits become true at specified amount of reads/writes, and thereafter once on every further 32 reads/writes.
    //
    index: u2 = undefined,
    status: u6 = undefined,

    // 1F801801h.Index0 - Command Register (W)
    //
    //   0-7  Command Byte
    //
    // Writing to this address sends the command byte to the CDROM controller, which will then read-out any Parameter byte(s) which have been previously stored in the Parameter Fifo. It takes a while until the command/parameters are transferred to the controller, and until the response bytes are received; once when completed, interrupt INT3 is generated (or INT5 in case of invalid command/parameter values), and the response (or error code) can be then read from the Response Fifo. Some commands additionally have a second response, which is sent with another interrupt.
    //
    command_port: u24 = undefined,
    // 1F801802h.Index0 - Parameter Fifo (W)
    //
    //   0-7  Parameter Byte(s) to be used for next Command
    //
    // Before sending a command, write any parameter byte(s) to this address.
    //
    // 1F801803h.Index0 - Request Register (W)
    //
    //   0-4 0    Not used (should be zero)
    //   5   SMEN Want Command Start Interrupt on Next Command (0=No change, 1=Yes)
    //   6   BFWR ...
    //   7   BFRD Want Data         (0=No/Reset Data Fifo, 1=Yes/Load Data Fifo)
    //
    //
    // 1F801802h.Index0..3 - Data Fifo - 8bit/16bit (R)
    // After ReadS/ReadN commands have generated INT1, software must set the Want Data bit (1F801803h.Index0.Bit7), then wait until Data Fifo becomes not empty (1F801800h.Bit6), the datablock (disk sector) can be then read from this register.
    //
    //   0-7  Data 8bit  (one byte), or alternately,
    //   0-15 Data 16bit (LSB=First byte, MSB=Second byte)
    //
    // The PSX hardware allows to read 800h-byte or 924h-byte sectors, indexed as [000h..7FFh] or [000h..923h], when trying to read further bytes, then the PSX will repeat the byte at index [800h-8] or [924h-4] as padding value.
    // Port 1F801802h can be accessed with 8bit or 16bit reads (ie. to read a 2048-byte sector, one can use 2048 load-byte opcodes, or 1024 load halfword opcodes, or, more conventionally, a 512 word DMA transfer; the actual CDROM databus is only 8bits wide, so CPU/DMA are apparently breaking 16bit/32bit reads into multiple 8bit reads from 1F801802h).
    //
    // 1F801801h.Index1 - Response Fifo (R)
    // 1F801801h.Index0,2,3 - Response Fifo (R) (Mirrors)
    //
    //   0-7  Response Byte(s) received after sending a Command
    //
    // The response Fifo is a 16-byte buffer, most or all responses are less than 16 bytes, after reading the last used byte (or before reading anything when the response is 0-byte long), Bit5 of the Index/Status register becomes zero to indicate that the last byte was received.
    // When reading further bytes: The buffer is padded with 00h's to the end of the 16-bytes, and does then restart at the first response byte (that, without receiving a new response, so it'll always return the same 16 bytes, until a new command/response has been sent/received).
    //
    // 1F801802h.Index1 - Interrupt Enable Register (W)
    // 1F801803h.Index0 - Interrupt Enable Register (R)
    // 1F801803h.Index2 - Interrupt Enable Register (R) (Mirror)
    //
    //   0-4  Interrupt Enable Bits (usually all set, ie. 1Fh=Enable All IRQs)
    //   5-7  Unknown/unused (write: should be zero) (read: usually all bits set)
    //
    // XXX WRITE: bit5-7 unused should be 0 // READ: bit5-7 unused
    //
    // 1F801803h.Index1 - Interrupt Flag Register (R/W)
    // 1F801803h.Index3 - Interrupt Flag Register (R) (Mirror)
    //
    //   0-2   Read: Response Received   Write: 7=Acknowledge   ;INT1..INT7
    //   3     Read: Unknown (usually 0) Write: 1=Acknowledge   ;INT8  ;XXX CLRBFEMPT
    //   4     Read: Command Start       Write: 1=Acknowledge   ;INT10h;XXX CLRBFWRDY
    //   5     Read: Always 1 ;XXX "_"   Write: 1=Unknown              ;XXX SMADPCLR
    //   6     Read: Always 1 ;XXX "_"   Write: 1=Reset Parameter Fifo ;XXX CLRPRM
    //   7     Read: Always 1 ;XXX "_"   Write: 1=Unknown              ;XXX CHPRST
    //
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
    //
    // 1F801802h.Index2 - Audio Volume for Left-CD-Out to Left-SPU-Input (W)
    // 1F801803h.Index2 - Audio Volume for Left-CD-Out to Right-SPU-Input (W)
    // 1F801801h.Index3 - Audio Volume for Right-CD-Out to Right-SPU-Input (W)
    // 1F801802h.Index3 - Audio Volume for Right-CD-Out to Left-SPU-Input (W)
    // Allows to configure the CD for mono/stereo output (eg. values "80h,0,80h,0" produce normal stereo volume, values "40h,40h,40h,40h" produce mono output of equivalent volume).
    // When using bigger values, the hardware does have some incomplete saturation support; the saturation works up to double volume (eg. overflows that occur on "FFh,0,FFh,0" or "80h,80h,80h,80h" are clipped to min/max levels), however, the saturation does NOT work properly when exceeding double volume (eg. mono with quad-volume "FFh,FFh,FFh,FFh").
    //
    //   0-7  Volume Level (00h..FFh) (00h=Off, FFh=Max/Double, 80h=Default/Normal)
    //
    // After changing these registers, write 20h to 1F801803h.Index3.
    // Unknown if any existing games are actually supporting mono output. Resident Evil 2 uses these ports to produce fade-in/fade-out effects (although, for that purpose, it should be much easier to use Port 1F801DB0h).
    //
    // 1F801803h.Index3 - Audio Volume Apply Changes (by writing bit5=1)
    //
    //   0    ADPMUTE Mute ADPCM                 (0=Normal, 1=Mute)
    //   1-4  -       Unused (should be zero)
    //   5    CHNGATV Apply Audio Volume changes (0=No change, 1=Apply)
    //   6-7  -       Unused (should be zero)
    //
    //
    // 1F801801h.Index1 - Sound Map Data Out (W)
    //
    //   0-7  Data
    //
    // This register seems to be restricted to 8bit bus, unknown if/how the PSX DMA controller can write to it (it might support only 16bit data for CDROM).
    //
    // 1F801801h.Index2 - Sound Map Coding Info (W)
    //
    //   0    Mono/Stereo     (0=Mono, 1=Stereo)
    //   1    Reserved        (0)
    //   2    Sample Rate     (0=37800Hz, 1=18900Hz)
    //   3    Reserved        (0)
    //   4    Bits per Sample (0=4bit, 1=8bit)
    //   5    Reserved        (0)
    //   6    Emphasis        (0=Off, 1=Emphasis)
    //   7    Reserved        (0)
    _unused: u96 = undefined,
};
