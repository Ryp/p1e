const std = @import("std");

const PSXState = @import("../state.zig").PSXState;
const cpu_execution = @import("../cpu/execution.zig");

pub fn reset_joy(psx: *PSXState) void {
    psx.mmio.ports.joy.baud = 0;
    psx.mmio.ports.joy.mode = @bitCast(@as(u16, 0));
    psx.mmio.ports.joy.ctrl.output_mode = .High;
    psx.mmio.ports.joy.ctrl.selected_slot = .Joy1;
    psx.mmio.ports.joy.ctrl.unknown_b3 = 0;
    psx.mmio.ports.joy.ctrl.unknown_b5 = 0;
    psx.mmio.ports.joy.stat.irq7_requested = false;

    psx.ports.controller1.graph = .Idle;
    psx.ports.controller2.graph = .Idle;
    // FIXME missing stuff most likely
}

pub const Key = enum {
    Up,
    Down,
    Cross,
};

pub fn send_key_press(psx: *PSXState, key: Key, is_pressed: bool) void {
    std.debug.print("Sending key {} pressed = {}\n", .{ key, is_pressed });

    switch (key) {
        .Up => {
            psx.ports.controller1.switches.lo.up = if (is_pressed) .Pressed else .Released;
        },
        .Down => {
            psx.ports.controller1.switches.lo.down = if (is_pressed) .Pressed else .Released;
        },
        .Cross => {
            psx.ports.controller1.switches.hi.cross = if (is_pressed) .Pressed else .Released;
        },
    }
}

pub fn execute_ticks(psx: *PSXState, ticks: u32) void {
    if (psx.ports.pending_irq7_ticks) |*pending_irq7_ticks| {
        if (pending_irq7_ticks.* > ticks) {
            pending_irq7_ticks.* -= ticks;
        } else {
            psx.ports.pending_irq7_ticks = null;

            psx.mmio.ports.joy.stat.irq7_requested = true;

            cpu_execution.request_hardware_interrupt(psx, .IRQ7_Controller_Memory_Card);
        }
    }
}
