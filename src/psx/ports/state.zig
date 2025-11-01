pub const PortsState = struct {
    joy: struct {
        rx_fifo: ?u8 = null, // FIFO in the docs, but it's normally 1 byte deep
    } = .{},

    pub fn write(self: @This(), writer: anytype) !void {
        if (self.joy.rx_fifo) |rx_fifo| {
            try writer.writeByte(1); // optional
            try writer.writeByte(rx_fifo); // value
        } else {
            try writer.writeByte(0); // optional flag
            try writer.writeByte(0); // value
        }
    }

    pub fn read(self: *@This(), reader: anytype) !void {
        const has_rx_fifo = try reader.takeByte() != 0;
        const rx_fifo_value = try reader.takeByte();

        self.joy.rx_fifo = if (has_rx_fifo) rx_fifo_value else null;
    }
};
