pub const GTEState = struct {
    data_regs: [32]u32 = undefined,
    ctrl_regs: [32]u32 = undefined,

    pub fn write(self: @This(), writer: anytype) !void {
        try writer.writeSliceEndian(u32, &self.data_regs, .little);
        try writer.writeSliceEndian(u32, &self.ctrl_regs, .little);
    }

    pub fn read(self: *@This(), reader: anytype) !void {
        try reader.readSliceEndian(u32, &self.data_regs, .little);
        try reader.readSliceEndian(u32, &self.ctrl_regs, .little);
    }
};
