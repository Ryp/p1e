const std = @import("std");
const vk = @import("vulkan");
const c = @import("c.zig");
const GraphicsContext = @import("graphics_context.zig").GraphicsContext;
const Swapchain = @import("swapchain.zig").Swapchain;
const Allocator = std.mem.Allocator;

const triangle_vert_spv align(@alignOf(u32)) = @embedFile("poly_vs").*;
const triangle_frag_spv align(@alignOf(u32)) = @embedFile("poly_fs").*;

const GPUTextureAccess = struct {
    stage_mask: vk.PipelineStageFlags2,
    access_mask: vk.AccessFlags2,
    image_layout: vk.ImageLayout,
};

const swapchain_access_initial = GPUTextureAccess{
    .stage_mask = .{ .bottom_of_pipe_bit = true },
    .access_mask = .{},
    .image_layout = .undefined,
};

const swapchain_access_present = GPUTextureAccess{
    .stage_mask = .{ .bottom_of_pipe_bit = true },
    .access_mask = .{},
    .image_layout = .present_src_khr,
};

const swapchain_access_render = GPUTextureAccess{
    .stage_mask = .{ .color_attachment_output_bit = true },
    .access_mask = .{ .color_attachment_write_bit = true },
    .image_layout = .attachment_optimal,
};

const ViewAspect = enum(u32) {
    Color = 1,
    Depth = 2,
    Stencil = 4,
};

const GPUTextureSubresource = struct {
    aspect: vk.ImageAspectFlags,
    mip_offset: u32,
    mip_count: u32,
    layer_offset: u32,
    layer_count: u32,
};

fn default_texture_subresource_one_color_mip(mip_index: u32, layer_index: u32) GPUTextureSubresource {
    return .{
        .aspect = .{ .color_bit = true },
        .mip_offset = mip_index,
        .mip_count = 1,
        .layer_offset = layer_index,
        .layer_count = 1,
    };
}

fn get_vk_image_subresource_range(subresource: GPUTextureSubresource) vk.ImageSubresourceRange {
    return .{
        .aspect_mask = subresource.aspect,
        .base_mip_level = subresource.mip_offset,
        .level_count = subresource.mip_count,
        .base_array_layer = subresource.layer_offset,
        .layer_count = subresource.layer_count,
    };
}

fn get_vk_image_barrier(handle: vk.Image, subresource: GPUTextureSubresource, src: GPUTextureAccess, dst: GPUTextureAccess, src_queue_family_index: u32, dst_queue_family_index: u32) vk.ImageMemoryBarrier2 {
    const view_range = get_vk_image_subresource_range(subresource);

    return .{
        .src_stage_mask = src.stage_mask,
        .src_access_mask = src.access_mask,
        .dst_stage_mask = dst.stage_mask,
        .dst_access_mask = dst.access_mask,
        .old_layout = src.image_layout,
        .new_layout = dst.image_layout,
        .src_queue_family_index = src_queue_family_index,
        .dst_queue_family_index = dst_queue_family_index,
        .image = handle,
        .subresource_range = view_range,
    };
}

fn get_vk_image_barrier_depency_info(barriers: []const vk.ImageMemoryBarrier2) vk.DependencyInfo {
    return .{
        .dependency_flags = .{},
        .memory_barrier_count = 0,
        .p_memory_barriers = null,
        .buffer_memory_barrier_count = 0,
        .p_buffer_memory_barriers = null,
        .image_memory_barrier_count = @intCast(barriers.len),
        .p_image_memory_barriers = @ptrCast(barriers),
    };
}

const Renderer = struct {
    dev: vk.Device,
    allocator: *Allocator,
};

const psx_state = @import("../psx/state.zig");
const cpu_execution = @import("../psx/cpu/execution.zig");
const gpu_execution = @import("../psx/gpu/execution.zig");

pub fn main(psx: *psx_state.PSXState, allocator: std.mem.Allocator) !void {
    // var renderer = try create_renderer(allocator, "PSX Emulator");
    // defer destroy_renderer(&renderer, allocator);
    const app_name = "PSX Emulator";

    if (c.glfwInit() != c.GLFW_TRUE) return error.GlfwInitFailed;
    defer c.glfwTerminate();

    if (c.glfwVulkanSupported() != c.GLFW_TRUE) {
        std.log.err("GLFW could not find libvulkan", .{});
        return error.NoVulkan;
    }

    var extent = vk.Extent2D{ .width = 800, .height = 600 };

    c.glfwWindowHint(c.GLFW_CLIENT_API, c.GLFW_NO_API);
    const window = c.glfwCreateWindow(
        @intCast(extent.width),
        @intCast(extent.height),
        app_name,
        null,
        null,
    ) orelse return error.WindowInitFailed;
    defer c.glfwDestroyWindow(window);

    const gc = try GraphicsContext.init(allocator, app_name, window);
    defer gc.deinit();

    std.log.debug("Using device: {s}", .{gc.deviceName()});

    var swapchain = try Swapchain.init(&gc, allocator, extent);
    defer swapchain.deinit();

    const desc_set_layout = try gc.dev.createDescriptorSetLayout(&.{
        .binding_count = 1,
        .p_bindings = &[_]vk.DescriptorSetLayoutBinding{.{
            .binding = 0,
            .descriptor_type = .storage_buffer,
            .descriptor_count = 1,
            .stage_flags = .{ .vertex_bit = true },
            .p_immutable_samplers = null,
        }},
    }, null);
    defer gc.dev.destroyDescriptorSetLayout(desc_set_layout, null);

    const pipeline_layout = try gc.dev.createPipelineLayout(&.{
        .flags = .{},
        .set_layout_count = 1,
        .p_set_layouts = @ptrCast(&desc_set_layout),
        .push_constant_range_count = 0,
        .p_push_constant_ranges = undefined,
    }, null);
    defer gc.dev.destroyPipelineLayout(pipeline_layout, null);

    const pipeline = try createPipeline(&gc, pipeline_layout, swapchain);
    defer gc.dev.destroyPipeline(pipeline, null);

    // Create descriptor pool
    const desc_pool = try gc.dev.createDescriptorPool(&.{
        .flags = .{},
        .max_sets = 1,
        .pool_size_count = 1,
        .p_pool_sizes = &[_]vk.DescriptorPoolSize{.{
            .type = .storage_buffer,
            .descriptor_count = 1,
        }},
    }, null);
    defer gc.dev.destroyDescriptorPool(desc_pool, null);

    // FIXME resettable flag?
    const pool = try gc.dev.createCommandPool(&.{
        .flags = .{ .reset_command_buffer_bit = true },
        .queue_family_index = gc.graphics_queue.family,
    }, null);
    defer gc.dev.destroyCommandPool(pool, null);

    var cmdbuf: vk.CommandBuffer = undefined;

    try gc.dev.allocateCommandBuffers(&.{
        .command_pool = pool,
        .level = .primary,
        .command_buffer_count = 1,
    }, @ptrCast(&cmdbuf));
    defer gc.dev.freeCommandBuffers(pool, 1, @ptrCast(&cmdbuf));

    const storage_buffer = try gc.dev.createBuffer(&.{
        .size = GraphicsContext.StagingBufferSizeBytes,
        .usage = .{ .transfer_dst_bit = true, .storage_buffer_bit = true },
        .sharing_mode = .exclusive,
    }, null);
    defer gc.dev.destroyBuffer(storage_buffer, null);

    const mem_reqs = gc.dev.getBufferMemoryRequirements(storage_buffer);

    const storage_buffer_memory = try gc.allocate(mem_reqs, .{
        // .device_local_bit = true,
        .host_coherent_bit = true,
    });
    defer gc.dev.freeMemory(storage_buffer_memory, null);

    try gc.dev.bindBufferMemory(storage_buffer, storage_buffer_memory, 0);

    // Create descirptor set
    var desc_set: [1]vk.DescriptorSet = undefined;
    try gc.dev.allocateDescriptorSets(&.{
        .descriptor_pool = desc_pool,
        .descriptor_set_count = 1,
        .p_set_layouts = @ptrCast(&desc_set_layout),
    }, @ptrCast(&desc_set));

    // Update descriptor set
    const desc_buffer_info = vk.DescriptorBufferInfo{
        .buffer = storage_buffer,
        .offset = 0,
        .range = GraphicsContext.StagingBufferSizeBytes,
    };

    const desc_writes = [_]vk.WriteDescriptorSet{.{
        .dst_set = desc_set[0],
        .dst_binding = 0,
        .dst_array_element = 0,
        .descriptor_count = 1,
        .descriptor_type = .storage_buffer,
        .p_image_info = undefined,
        .p_buffer_info = @ptrCast(&desc_buffer_info),
        .p_texel_buffer_view = undefined,
    }};

    gc.dev.updateDescriptorSets(1, @ptrCast(&desc_writes), 0, null);

    var w: c_int = undefined;
    var h: c_int = undefined;
    c.glfwGetFramebufferSize(window, &w, &h);

    var should_recreate_swapchain = false;

    psx.headless = false; // Hook backend

    while (c.glfwWindowShouldClose(window) == c.GLFW_FALSE) {
        c.glfwPollEvents();
        c.glfwGetFramebufferSize(window, &w, &h);

        while (!psx.gpu.pending_draw) {
            cpu_execution.step(psx);
        }

        const fence_wait_result = try gc.dev.waitForFences(1, @ptrCast(&gc.frame_fence), vk.TRUE, std.math.maxInt(u64));
        std.debug.assert(fence_wait_result == .success);

        try gc.dev.resetFences(1, @ptrCast(&gc.frame_fence));

        if (should_recreate_swapchain) {
            try swapchain.recreate(extent);
            should_recreate_swapchain = false;
        }

        const state = swapchain.acquire_next_image(gc.image_acquired) catch |err| switch (err) {
            error.OutOfDateKHR => Swapchain.PresentState.suboptimal,
            else => |narrow| return narrow,
        };

        if (state == .suboptimal or extent.width != @as(u32, @intCast(w)) or extent.height != @as(u32, @intCast(h))) {
            extent.width = @intCast(w);
            extent.height = @intCast(h);

            should_recreate_swapchain = true;
        }

        try gc.dev.resetCommandPool(pool, .{});

        try gc.dev.beginCommandBuffer(cmdbuf, &.{});

        var vertex_count: u32 = 0;

        {
            const data = try gc.dev.mapMemory(storage_buffer_memory, 0, vk.WHOLE_SIZE, .{});
            defer gc.dev.unmapMemory(storage_buffer_memory);

            const data_ptr: [*]f32 = @ptrCast(@alignCast(data));
            var data_index: u32 = 0;

            for (psx.gpu.draw_command_buffer[0..psx.gpu.draw_command_offset], 0..) |draw_command, command_index| {
                std.debug.print("Command index = {}\n", .{command_index});
                for (psx.gpu.index_buffer[draw_command.index_offset .. draw_command.index_offset + draw_command.index_count]) |index| {
                    const phat_vertex = psx.gpu.vertex_buffer[index];
                    data_ptr[data_index + 0] = phat_vertex.position[0] / 1024.0;
                    data_ptr[data_index + 1] = phat_vertex.position[1] / 512.0;
                    data_ptr[data_index + 2] = phat_vertex.color[0];
                    data_ptr[data_index + 3] = phat_vertex.color[1];
                    data_ptr[data_index + 4] = phat_vertex.color[2];
                    data_index += 5;
                }
                vertex_count += draw_command.index_count;
            }

            // const gpu_vertices: [*]Vertex = @ptrCast(@alignCast(data));
            // @memcpy(gpu_vertices, vertices[0..]);
        }

        // const region = vk.BufferCopy{
        //     .src_offset = 0,
        //     .dst_offset = 0,
        //     .size = 100,
        // };

        // try cmdbuf.copyBuffer(storage_buffer, gc.staging_buffer, 1, @ptrCast(&region));

        //  FIXME
        gc.dev.cmdBindDescriptorSets(cmdbuf, .graphics, pipeline_layout, 0, 1, @ptrCast(&desc_set), 0, null);

        try record_command_buffer(&gc, cmdbuf, &swapchain, pipeline, vertex_count);

        try gc.dev.endCommandBuffer(cmdbuf);

        const wait_stage = [_]vk.PipelineStageFlags{.{ .bottom_of_pipe_bit = true }};
        try gc.dev.queueSubmit(gc.graphics_queue.handle, 1, &[_]vk.SubmitInfo{.{
            .wait_semaphore_count = 1,
            .p_wait_semaphores = @ptrCast(&gc.image_acquired),
            .p_wait_dst_stage_mask = &wait_stage,
            .command_buffer_count = 1,
            .p_command_buffers = @ptrCast(&cmdbuf),
            .signal_semaphore_count = 1,
            .p_signal_semaphores = @ptrCast(&gc.render_finished),
        }}, gc.frame_fence);

        const present_result = try gc.dev.queuePresentKHR(gc.present_queue.handle, &.{
            .wait_semaphore_count = 1,
            .p_wait_semaphores = @ptrCast(&gc.render_finished),
            .swapchain_count = 1,
            .p_swapchains = @ptrCast(&swapchain.handle),
            .p_image_indices = @ptrCast(&swapchain.image_index),
        });

        if (present_result == .error_out_of_date_khr or present_result == .suboptimal_khr) {
            should_recreate_swapchain = true;
        } else {
            std.debug.assert(present_result == .success);
        }

        gpu_execution.consume_pending_draw(psx);
    }

    const result = try gc.dev.waitForFences(1, @ptrCast(&gc.frame_fence), vk.TRUE, std.math.maxInt(u64));
    std.debug.assert(result == .success);

    try gc.dev.deviceWaitIdle();
}

fn record_command_buffer(
    gc: *const GraphicsContext,
    cmdbuf: vk.CommandBuffer,
    swapchain: *Swapchain,
    pipeline: vk.Pipeline,
    vertex_count: u32,
) !void {
    if (swapchain.needs_transition) {
        var image_barriers = try std.BoundedArray(vk.ImageMemoryBarrier2, 8).init(swapchain.swap_images.len);

        for (swapchain.swap_images, 0..) |swapchain_image, swapchain_image_index| {
            const src = swapchain_access_initial;
            const dst = if (swapchain_image_index == swapchain.image_index)
                swapchain_access_render
            else
                swapchain_access_present;

            const subresource = default_texture_subresource_one_color_mip(0, 0);

            image_barriers.slice()[swapchain_image_index] = get_vk_image_barrier(swapchain_image.image, subresource, src, dst, 0, 0);
        }

        const dependencies = get_vk_image_barrier_depency_info(image_barriers.constSlice());

        gc.dev.cmdPipelineBarrier2(cmdbuf, &dependencies);

        swapchain.needs_transition = false;
    } else {
        const subresource = default_texture_subresource_one_color_mip(0, 0);

        const image_barrier = get_vk_image_barrier(swapchain.swap_images[swapchain.image_index].image, subresource, swapchain_access_present, swapchain_access_render, 0, 0);
        const image_barriers: [1]vk.ImageMemoryBarrier2 = .{image_barrier};

        const dependencies = get_vk_image_barrier_depency_info(&image_barriers);

        gc.dev.cmdPipelineBarrier2(cmdbuf, &dependencies);
    }

    const clear_value = vk.ClearValue{
        .color = .{ .float_32 = .{ 0, 0, 0, 1 } },
    };

    const viewport = vk.Viewport{
        .x = 0,
        .y = 0,
        .width = @floatFromInt(swapchain.extent.width),
        .height = @floatFromInt(swapchain.extent.height),
        .min_depth = 0,
        .max_depth = 1,
    };

    const scissor = vk.Rect2D{
        .offset = .{ .x = 0, .y = 0 },
        .extent = swapchain.extent,
    };

    gc.dev.cmdSetViewport(cmdbuf, 0, 1, @ptrCast(&viewport));
    gc.dev.cmdSetScissor(cmdbuf, 0, 1, @ptrCast(&scissor));

    // This needs to be a separate definition - see https://github.com/ziglang/zig/issues/7627.
    const render_area = vk.Rect2D{
        .offset = .{ .x = 0, .y = 0 },
        .extent = swapchain.extent,
    };

    const swapchain_image_attachment_info = vk.RenderingAttachmentInfo{
        .image_view = swapchain.swap_images[swapchain.image_index].view, // FIXME careful with the index and when it's updated!
        .image_layout = .color_attachment_optimal,
        .resolve_mode = .{},
        .resolve_image_view = .null_handle,
        .resolve_image_layout = .undefined,
        .load_op = .load,
        .store_op = .store,
        .clear_value = clear_value,
    };
    const rendering_info = vk.RenderingInfo{
        .render_area = render_area,
        .layer_count = 1,
        .view_mask = 0,
        .color_attachment_count = 1,
        .p_color_attachments = @ptrCast(&swapchain_image_attachment_info),
        .p_depth_attachment = null,
        .p_stencil_attachment = null,
    };

    gc.dev.cmdBeginRendering(cmdbuf, &rendering_info);

    gc.dev.cmdBindPipeline(cmdbuf, .graphics, pipeline);

    gc.dev.cmdDraw(cmdbuf, vertex_count, 1, 0, 0);

    gc.dev.cmdEndRendering(cmdbuf);

    {
        const subresource = default_texture_subresource_one_color_mip(0, 0);

        const image_barrier = get_vk_image_barrier(swapchain.swap_images[swapchain.image_index].image, subresource, swapchain_access_render, swapchain_access_present, 0, 0);
        const image_barriers: [1]vk.ImageMemoryBarrier2 = .{image_barrier};

        const dependencies = get_vk_image_barrier_depency_info(&image_barriers);

        gc.dev.cmdPipelineBarrier2(cmdbuf, &dependencies);
    }
}

fn createPipeline(
    gc: *const GraphicsContext,
    layout: vk.PipelineLayout,
    swapchain: Swapchain,
) !vk.Pipeline {
    const vert = try gc.dev.createShaderModule(&.{
        .code_size = triangle_vert_spv.len,
        .p_code = @ptrCast(&triangle_vert_spv),
    }, null);
    defer gc.dev.destroyShaderModule(vert, null);

    const frag = try gc.dev.createShaderModule(&.{
        .code_size = triangle_frag_spv.len,
        .p_code = @ptrCast(&triangle_frag_spv),
    }, null);
    defer gc.dev.destroyShaderModule(frag, null);

    const pssci = [_]vk.PipelineShaderStageCreateInfo{
        .{
            .stage = .{ .vertex_bit = true },
            .module = vert,
            .p_name = "main",
        },
        .{
            .stage = .{ .fragment_bit = true },
            .module = frag,
            .p_name = "main",
        },
    };

    const pvisci = vk.PipelineVertexInputStateCreateInfo{
        .vertex_binding_description_count = 0,
        .p_vertex_binding_descriptions = null,
        .vertex_attribute_description_count = 0,
        .p_vertex_attribute_descriptions = null,
    };

    const piasci = vk.PipelineInputAssemblyStateCreateInfo{
        .topology = .triangle_list,
        .primitive_restart_enable = vk.FALSE,
    };

    const pvsci = vk.PipelineViewportStateCreateInfo{
        .viewport_count = 1,
        .p_viewports = undefined, // Dynamic
        .scissor_count = 1,
        .p_scissors = undefined, // Dynamic
    };

    const prsci = vk.PipelineRasterizationStateCreateInfo{
        .depth_clamp_enable = vk.FALSE,
        .rasterizer_discard_enable = vk.FALSE,
        .polygon_mode = .fill,
        .cull_mode = .{ .back_bit = false },
        .front_face = .clockwise,
        .depth_bias_enable = vk.FALSE,
        .depth_bias_constant_factor = 0,
        .depth_bias_clamp = 0,
        .depth_bias_slope_factor = 0,
        .line_width = 1,
    };

    const pmsci = vk.PipelineMultisampleStateCreateInfo{
        .rasterization_samples = .{ .@"1_bit" = true },
        .sample_shading_enable = vk.FALSE,
        .min_sample_shading = 1,
        .alpha_to_coverage_enable = vk.FALSE,
        .alpha_to_one_enable = vk.FALSE,
    };

    const pcbas = vk.PipelineColorBlendAttachmentState{
        .blend_enable = vk.FALSE,
        .src_color_blend_factor = .one,
        .dst_color_blend_factor = .zero,
        .color_blend_op = .add,
        .src_alpha_blend_factor = .one,
        .dst_alpha_blend_factor = .zero,
        .alpha_blend_op = .add,
        .color_write_mask = .{ .r_bit = true, .g_bit = true, .b_bit = true, .a_bit = true },
    };

    const pcbsci = vk.PipelineColorBlendStateCreateInfo{
        .logic_op_enable = vk.FALSE,
        .logic_op = .copy,
        .attachment_count = 1,
        .p_attachments = @ptrCast(&pcbas),
        .blend_constants = [_]f32{ 0, 0, 0, 0 },
    };

    const pipeline_rendering = vk.PipelineRenderingCreateInfo{
        .view_mask = 0,
        .color_attachment_count = 1,
        .p_color_attachment_formats = @ptrCast(&swapchain.surface_format.format),
        .depth_attachment_format = .undefined,
        .stencil_attachment_format = .undefined,
    };

    const dynstate = [_]vk.DynamicState{ .viewport, .scissor };
    const pdsci = vk.PipelineDynamicStateCreateInfo{
        .flags = .{},
        .dynamic_state_count = dynstate.len,
        .p_dynamic_states = &dynstate,
    };

    const gpci = vk.GraphicsPipelineCreateInfo{
        .p_next = @ptrCast(&pipeline_rendering),
        .flags = .{},
        .stage_count = 2,
        .p_stages = &pssci,
        .p_vertex_input_state = &pvisci,
        .p_input_assembly_state = &piasci,
        .p_tessellation_state = null,
        .p_viewport_state = &pvsci,
        .p_rasterization_state = &prsci,
        .p_multisample_state = &pmsci,
        .p_depth_stencil_state = null,
        .p_color_blend_state = &pcbsci,
        .p_dynamic_state = &pdsci,
        .layout = layout,
        .render_pass = .null_handle,
        .subpass = 0,
        .base_pipeline_handle = .null_handle,
        .base_pipeline_index = -1,
    };

    var pipeline: vk.Pipeline = undefined;
    _ = try gc.dev.createGraphicsPipelines(
        .null_handle,
        1,
        @ptrCast(&gpci),
        null,
        @ptrCast(&pipeline),
    );
    return pipeline;
}
