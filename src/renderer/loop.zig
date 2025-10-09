const std = @import("std");

const build_options = @import("build_options");

const cpu_execution = @import("../psx/cpu/execution.zig");
const PSXState = @import("../psx/state.zig").PSXState;

const sdl = @import("../sdl.zig");

pub fn run(psx: *PSXState, allocator: std.mem.Allocator) !void {
    if (build_options.enable_vulkan_backend) {
        const triangle = @import("triangle.zig");
        try triangle.main(psx, allocator);
    } else if (true) {
        try sdl.execute_main_loop(psx, allocator);
    } else {
        while (true) {
            cpu_execution.step_1k_times(psx);
        }
    }
}
