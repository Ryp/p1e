const std = @import("std");

const PSXState = @import("../state.zig").PSXState;
const mmio = @import("../mmio.zig");
const gpu_execution = @import("../gpu/execution.zig");

const dma_mmio = @import("mmio.zig");

pub fn execute_dma_transfer(psx: *PSXState, channel: *dma_mmio.DMAChannel, channel_index: dma_mmio.DMAChannelIndex) void {
    // std.debug.print("DMA Transfer {} in mode {}\n", .{ channel_index, channel.channel_control.sync_mode });

    switch (channel.channel_control.sync_mode) {
        .Manual, .Request => {
            var address = channel.base_address.offset;
            var word_count_left = get_transfer_word_count(channel);

            while (word_count_left > 0) : (address = switch (channel.channel_control.adress_step) {
                .Inc4 => address +% 4,
                .Dec4 => address -% 4,
            }) {
                const address_masked = address & 0x00_1f_ff_fc;

                switch (channel.channel_control.transfer_direction) {
                    .ToRAM => {
                        switch (channel_index) {
                            .Channel0_MDEC_IN, .Channel1_MDEC_OUT, .Channel3_SPU, .Channel4_CDROM, .Channel5_PIO => {
                                std.debug.print("DMA transfer to RAM on channel {} not implemented yet\n", .{channel_index});
                                unreachable;
                            },
                            .Channel2_GPU => {
                                const command_word = gpu_execution.load_gpuread_u32(psx);
                                mmio.store_u32(psx, address_masked, command_word);
                            },
                            .Channel6_OTC => {
                                const src_word = switch (word_count_left) {
                                    1 => 0x00_ff_ff_ff,
                                    else => (address -% 4) & 0x00_1f_ff_ff,
                                };

                                mmio.store_u32(psx, address_masked, src_word);
                            },
                            .Invalid => unreachable,
                        }
                    },
                    .FromRAM => {
                        switch (channel_index) {
                            .Channel2_GPU => {
                                const command_word = mmio.load_u32(psx, address_masked);

                                gpu_execution.store_gp0_u32(psx, command_word);
                            },
                            .Channel0_MDEC_IN, .Channel1_MDEC_OUT, .Channel3_SPU, .Channel4_CDROM, .Channel5_PIO, .Channel6_OTC => {
                                unreachable; // FIXME
                            },
                            .Invalid => unreachable,
                        }
                    },
                }

                word_count_left -= 1;
            }
        },
        .LinkedList => {
            std.debug.assert(channel_index == .Channel2_GPU);
            std.debug.assert(channel.channel_control.transfer_direction == .FromRAM);
            std.debug.assert(channel.block_control.linked_list.zero_b0_31 == 0);

            var header_address: u24 = channel.base_address.offset & 0x1f_ff_fc;

            const GPUCommandHeader = packed struct {
                next_address: u24,
                word_count: u8,
            };

            while (true) {
                const header: GPUCommandHeader = @bitCast(mmio.load_u32(psx, header_address));

                for (0..header.word_count) |word_index| {
                    const command_word_address = (header_address + 4 * @as(u24, @intCast(word_index + 1))) & 0x1f_ff_fc;
                    const command_word = mmio.load_u32(psx, command_word_address);

                    gpu_execution.store_gp0_u32(psx, command_word);
                }

                // Look for end-of-list marker (mednafen does this instead of checking for 0x00_ff_ff_ff)
                if (header.next_address & 0x80_00_00 != 0) {
                    break;
                }

                header_address = header.next_address & 0x1f_ff_fc;
            }
        },
        .Reserved => unreachable,
    }

    channel.channel_control.status = .StoppedOrCompleted;
    channel.channel_control.start_or_trigger = 0;
    // FIXME reset more fields
}

fn get_transfer_word_count(channel: *dma_mmio.DMAChannel) u32 {
    return switch (channel.channel_control.sync_mode) {
        .Manual => channel.block_control.manual.word_count,
        .Request => channel.block_control.request.block_count * channel.block_control.request.block_size,
        .LinkedList, .Reserved => unreachable,
    };
}
