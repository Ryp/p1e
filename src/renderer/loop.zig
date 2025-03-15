const std = @import("std");

const build_options = @import("build_options");

const cpu_execution = @import("../psx/cpu/execution.zig");
const psx_state = @import("../psx/state.zig");
const PSXState = psx_state.PSXState;

pub fn run(psx: *PSXState, allocator: std.mem.Allocator) !void {
    if (build_options.enable_vulkan_backend) {
        const triangle = @import("triangle.zig");
        try triangle.main(psx, allocator);
    } else {
        while (true) {
            cpu_execution.step(psx);
        }
    }
}
