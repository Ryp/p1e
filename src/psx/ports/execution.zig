const PSXState = @import("../state.zig").PSXState;

pub fn reset_joy(psx: *PSXState) void {
    psx.mmio.ports.joy.baud = 0;
    psx.mmio.ports.joy.mode = @bitCast(@as(u16, 0));
    psx.mmio.ports.joy.ctrl.output_mode = .High;
    psx.mmio.ports.joy.ctrl.selected_slot = .Joy1;
    psx.mmio.ports.joy.ctrl.unknown_b3 = 0;
    psx.mmio.ports.joy.ctrl.unknown_b5 = 0;
    psx.mmio.ports.joy.stat.irq7_requested = false;
    // FIXME missing stuff most likely
}
