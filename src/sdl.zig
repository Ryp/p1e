const std = @import("std");

const tracy = @import("tracy.zig");

const c = @cImport({
    @cInclude("SDL3/SDL.h");
});

const PSXState = @import("psx/state.zig").PSXState;
const cpu_execution = @import("psx/cpu/execution.zig");
const pixel_format = @import("psx/gpu/pixel_format.zig");

pub fn execute_main_loop(psx: *PSXState, allocator: std.mem.Allocator) !void {
    const width = 1024;
    const height = 512;

    if (!c.SDL_Init(c.SDL_INIT_VIDEO | c.SDL_INIT_EVENTS)) {
        c.SDL_Log("Unable to initialize SDL: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    }
    defer c.SDL_Quit();

    const window = c.SDL_CreateWindow("p1e", @as(c_int, @intCast(width)), @as(c_int, @intCast(height)), 0) orelse {
        c.SDL_Log("Unable to create window: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    defer c.SDL_DestroyWindow(window);

    if (!c.SDL_SetHint(c.SDL_HINT_RENDER_VSYNC, "1")) {
        c.SDL_Log("Unable to set hint: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    }

    const ren = c.SDL_CreateRenderer(window, null) orelse {
        c.SDL_Log("Unable to create renderer: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    defer c.SDL_DestroyRenderer(ren);

    const title_string = try allocator.alloc(u8, 1024);
    defer allocator.free(title_string);

    const backbuffer = try allocator.alloc(pixel_format.PackedRGBA8, 1024 * 512);
    defer allocator.free(backbuffer);

    var shouldExit = false;

    var last_frame_time_ms: u64 = c.SDL_GetTicks();

    while (!shouldExit) {
        const current_frame_time_ms: u64 = c.SDL_GetTicks();
        const frame_delta_secs = @as(f32, @floatFromInt(current_frame_time_ms - last_frame_time_ms)) * 0.001;

        var sdlEvent: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&sdlEvent)) {
            switch (sdlEvent.type) {
                c.SDL_EVENT_QUIT => {
                    shouldExit = true;
                },
                c.SDL_EVENT_KEY_DOWN => {
                    if (sdlEvent.key.key == c.SDLK_ESCAPE)
                        shouldExit = true;
                },
                else => {},
            }
        }

        {
            const tr_step = tracy.trace(@src());
            defer tr_step.end();
            for (0..200) |_| {
                cpu_execution.step_1k_times(psx);
            }
        }

        // Set window title
        _ = std.fmt.bufPrintZ(title_string, "p1e | frame time {d:.1} ms", .{frame_delta_secs * 1000.0}) catch unreachable;
        _ = c.SDL_SetWindowTitle(window, title_string.ptr);

        _ = c.SDL_SetRenderDrawColor(ren, 0, 0, 0, c.SDL_ALPHA_OPAQUE);
        _ = c.SDL_RenderClear(ren);

        {
            const tr_present = tracy.traceNamed(@src(), "Fill backbuffer");
            defer tr_present.end();
            const psx_vram_typed = std.mem.bytesAsSlice(pixel_format.PackedRGB5A1, psx.gpu.vram);

            for (backbuffer, psx_vram_typed) |*out, in| {
                out.* = pixel_format.convert_rgb5a1_to_rgba8(in);
                out.a = 255;
            }
        }

        const texture = c.SDL_CreateTexture(ren, c.SDL_PIXELFORMAT_ABGR8888, c.SDL_TEXTUREACCESS_STATIC, 1024, 512);
        defer c.SDL_DestroyTexture(texture);

        // Match SDL2 behavior
        _ = c.SDL_SetTextureScaleMode(texture, c.SDL_SCALEMODE_NEAREST);

        _ = c.SDL_UpdateTexture(texture, null, @ptrCast(backbuffer.ptr), 1024 * @sizeOf(u32));

        _ = c.SDL_RenderTexture(ren, texture, null, null);

        // const present_scope = tracy.traceNamed(@src(), "SDL Wait for present");
        // defer present_scope.end();

        {
            const tr_present = tracy.traceNamed(@src(), "Present");
            defer tr_present.end();
            _ = c.SDL_RenderPresent(ren);
        }

        last_frame_time_ms = current_frame_time_ms;
    }
}
