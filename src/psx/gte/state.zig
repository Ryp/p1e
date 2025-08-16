pub const GTEState = struct {
    data_regs: [32]u32 = undefined,
    ctrl_regs: [32]u32 = undefined,

    pub fn write(self: @This(), writer: anytype) !void {
        // FIXME
        _ = self;
        _ = writer;
    }

    pub fn read(self: *@This(), reader: anytype) !void {
        // FIXME
        _ = self;
        _ = reader;
    }
};
