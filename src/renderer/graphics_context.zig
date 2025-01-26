const std = @import("std");
const vk = @import("vulkan");
const c = @import("c.zig");
const Allocator = std.mem.Allocator;

const required_instance_extensions = [_][*:0]const u8{
    vk.extensions.ext_debug_utils.name,
};

const enabled_instance_layers = [_][*:0]const u8{
    "VK_LAYER_KHRONOS_validation",
};

const required_device_extensions = [_][*:0]const u8{
    vk.extensions.khr_swapchain.name,
};

/// To construct base, instance and device wrappers for vulkan-zig, you need to pass a list of 'apis' to it.
const apis: []const vk.ApiInfo = &.{
    // You can either add invidiual functions by manually creating an 'api'
    .{
        .base_commands = .{
            .createInstance = true,
        },
        .instance_commands = .{
            .createDevice = true,
        },
    },
    // Or you can add entire feature sets or extensions
    vk.features.version_1_0,
    vk.features.version_1_3,
    vk.extensions.ext_debug_utils,
    vk.extensions.khr_surface,
    vk.extensions.khr_swapchain,
};

/// Next, pass the `apis` to the wrappers to create dispatch tables.
const BaseDispatch = vk.BaseWrapper(apis);
const InstanceDispatch = vk.InstanceWrapper(apis);
const DeviceDispatch = vk.DeviceWrapper(apis);

// Also create some proxying wrappers, which also have the respective handles
const Instance = vk.InstanceProxy(apis);
const Device = vk.DeviceProxy(apis);

pub const GraphicsContext = struct {
    pub const CommandBuffer = vk.CommandBufferProxy(apis);

    allocator: Allocator,

    vkb: BaseDispatch,

    instance: Instance,
    surface: vk.SurfaceKHR,
    pdev: vk.PhysicalDevice,
    props: vk.PhysicalDeviceProperties,
    mem_props: vk.PhysicalDeviceMemoryProperties,
    frame_fence: vk.Fence,
    image_acquired: vk.Semaphore,
    render_finished: vk.Semaphore,

    debug_utils_messenger: vk.DebugUtilsMessengerEXT,

    dev: Device,
    graphics_queue: Queue,
    present_queue: Queue,

    pub fn init(allocator: Allocator, app_name: [*:0]const u8, window: *c.GLFWwindow) !GraphicsContext {
        var self: GraphicsContext = undefined;
        self.allocator = allocator;
        self.vkb = try BaseDispatch.load(c.glfwGetInstanceProcAddress);

        var glfw_exts_count: u32 = 0;
        const glfw_exts = c.glfwGetRequiredInstanceExtensions(&glfw_exts_count);

        const propsv_instance = try self.vkb.enumerateInstanceExtensionPropertiesAlloc(null, allocator);
        defer allocator.free(propsv_instance);

        for (required_instance_extensions) |ext| {
            for (propsv_instance) |props| {
                if (std.mem.eql(u8, std.mem.span(ext), std.mem.sliceTo(&props.extension_name, 0))) {
                    break;
                }
            } else {
                std.debug.print("required instance extension {s} not supported\n", .{ext});
                unreachable;
            }
        }

        var enabled_instance_extensions = try allocator.alloc([*:0]const u8, glfw_exts_count + required_instance_extensions.len);
        defer allocator.free(enabled_instance_extensions);

        if (glfw_exts_count > 0) {
            for (enabled_instance_extensions[0..glfw_exts_count], glfw_exts[0..glfw_exts_count]) |*ext, glfw_ext| {
                ext.* = glfw_ext;
            }
        }

        for (enabled_instance_extensions[glfw_exts_count..], required_instance_extensions) |*ext, required_ext_name| {
            ext.* = required_ext_name;
        }

        const app_info = vk.ApplicationInfo{
            .p_application_name = app_name,
            .application_version = vk.makeApiVersion(0, 0, 0, 0),
            .p_engine_name = app_name,
            .engine_version = vk.makeApiVersion(0, 0, 0, 0),
            .api_version = vk.API_VERSION_1_3,
        };

        const instance = try self.vkb.createInstance(&.{
            .p_application_info = &app_info,
            .enabled_layer_count = @intCast(enabled_instance_layers.len),
            .pp_enabled_layer_names = @ptrCast(&enabled_instance_layers),
            .enabled_extension_count = @intCast(enabled_instance_extensions.len),
            .pp_enabled_extension_names = @ptrCast(enabled_instance_extensions),
        }, null);

        const vki = try allocator.create(InstanceDispatch);
        errdefer allocator.destroy(vki);
        vki.* = try InstanceDispatch.load(instance, self.vkb.dispatch.vkGetInstanceProcAddr);
        self.instance = Instance.init(instance, vki);
        errdefer self.instance.destroyInstance(null);

        const callbackCreateInfo = vk.DebugUtilsMessengerCreateInfoEXT{
            .flags = .{},
            .message_severity = .{ .verbose_bit_ext = true, .info_bit_ext = true, .warning_bit_ext = true, .error_bit_ext = true },
            .message_type = .{ .general_bit_ext = true, .validation_bit_ext = true, .performance_bit_ext = true },
            .pfn_user_callback = @ptrCast(&debug_message_callback),
            .p_user_data = null, // FIXME
        };

        self.debug_utils_messenger = try self.instance.createDebugUtilsMessengerEXT(&callbackCreateInfo, null);
        errdefer self.instance.destroyDebugUtilsMessengerEXT(self.debug_utils_messenger, null);

        self.surface = try createSurface(self.instance, window);
        errdefer self.instance.destroySurfaceKHR(self.surface, null);

        const candidate = try pickPhysicalDevice(self.instance, allocator, self.surface);
        self.pdev = candidate.pdev;
        self.props = candidate.props;

        const dev = try initializeCandidate(self.instance, candidate);

        const vkd = try allocator.create(DeviceDispatch);
        errdefer allocator.destroy(vkd);
        vkd.* = try DeviceDispatch.load(dev, self.instance.wrapper.dispatch.vkGetDeviceProcAddr);
        self.dev = Device.init(dev, vkd);
        errdefer self.dev.destroyDevice(null);

        self.graphics_queue = Queue.init(self.dev, candidate.queues.graphics_family);
        self.present_queue = Queue.init(self.dev, candidate.queues.present_family);

        self.mem_props = self.instance.getPhysicalDeviceMemoryProperties(self.pdev);

        self.frame_fence = try self.dev.createFence(&.{ .flags = .{ .signaled_bit = true } }, null);
        errdefer self.dev.destroyFence(self.frame_fence, null);

        try self.dev.setDebugUtilsObjectNameEXT(&.{ .object_type = .fence, .object_handle = @intFromEnum(self.frame_fence), .p_object_name = "Frame fence" });

        self.image_acquired = try self.dev.createSemaphore(&.{}, null);
        errdefer self.dev.destroySemaphore(self.image_acquired, null);

        try self.dev.setDebugUtilsObjectNameEXT(&.{ .object_type = .semaphore, .object_handle = @intFromEnum(self.image_acquired), .p_object_name = "Image acquired" });

        self.render_finished = try self.dev.createSemaphore(&.{}, null);
        errdefer self.dev.destroySemaphore(self.render_finished, null);

        try self.dev.setDebugUtilsObjectNameEXT(&.{ .object_type = .semaphore, .object_handle = @intFromEnum(self.render_finished), .p_object_name = "Rendering finished" });

        return self;
    }

    pub fn deinit(self: GraphicsContext) void {
        self.dev.destroyFence(self.frame_fence, null);
        self.dev.destroySemaphore(self.image_acquired, null);
        self.dev.destroySemaphore(self.render_finished, null);

        self.dev.destroyDevice(null);

        self.instance.destroyDebugUtilsMessengerEXT(self.debug_utils_messenger, null);

        self.instance.destroySurfaceKHR(self.surface, null);
        self.instance.destroyInstance(null);

        // Don't forget to free the tables to prevent a memory leak.
        self.allocator.destroy(self.dev.wrapper);
        self.allocator.destroy(self.instance.wrapper);
    }

    pub fn deviceName(self: *const GraphicsContext) []const u8 {
        return std.mem.sliceTo(&self.props.device_name, 0);
    }

    pub fn findMemoryTypeIndex(self: GraphicsContext, memory_type_bits: u32, flags: vk.MemoryPropertyFlags) !u32 {
        for (self.mem_props.memory_types[0..self.mem_props.memory_type_count], 0..) |mem_type, i| {
            if (memory_type_bits & (@as(u32, 1) << @truncate(i)) != 0 and mem_type.property_flags.contains(flags)) {
                return @truncate(i);
            }
        }

        return error.NoSuitableMemoryType;
    }

    pub fn allocate(self: GraphicsContext, requirements: vk.MemoryRequirements, flags: vk.MemoryPropertyFlags) !vk.DeviceMemory {
        return try self.dev.allocateMemory(&.{
            .allocation_size = requirements.size,
            .memory_type_index = try self.findMemoryTypeIndex(requirements.memory_type_bits, flags),
        }, null);
    }
};

pub const Queue = struct {
    handle: vk.Queue,
    family: u32,

    fn init(device: Device, family: u32) Queue {
        return .{
            .handle = device.getDeviceQueue(family, 0),
            .family = family,
        };
    }
};

fn createSurface(instance: Instance, window: *c.GLFWwindow) !vk.SurfaceKHR {
    var surface: vk.SurfaceKHR = undefined;
    if (c.glfwCreateWindowSurface(instance.handle, window, null, &surface) != .success) {
        return error.SurfaceInitFailed;
    }

    return surface;
}

fn initializeCandidate(instance: Instance, candidate: DeviceCandidate) !vk.Device {
    const priority = [_]f32{1};
    const qci = [_]vk.DeviceQueueCreateInfo{
        .{
            .queue_family_index = candidate.queues.graphics_family,
            .queue_count = 1,
            .p_queue_priorities = &priority,
        },
        .{
            .queue_family_index = candidate.queues.present_family,
            .queue_count = 1,
            .p_queue_priorities = &priority,
        },
    };

    const queue_count: u32 = if (candidate.queues.graphics_family == candidate.queues.present_family)
        1
    else
        2;

    const features_vk_1_3 = vk.PhysicalDeviceVulkan13Features{
        .synchronization_2 = vk.TRUE,
        .dynamic_rendering = vk.TRUE,
    };

    return try instance.createDevice(candidate.pdev, &.{
        .p_next = @ptrCast(&features_vk_1_3),
        .queue_create_info_count = queue_count,
        .p_queue_create_infos = &qci,
        .enabled_extension_count = required_device_extensions.len,
        .pp_enabled_extension_names = @ptrCast(&required_device_extensions),
    }, null);
}

const DeviceCandidate = struct {
    pdev: vk.PhysicalDevice,
    props: vk.PhysicalDeviceProperties,
    queues: QueueAllocation,
};

const QueueAllocation = struct {
    graphics_family: u32,
    present_family: u32,
};

fn pickPhysicalDevice(
    instance: Instance,
    allocator: Allocator,
    surface: vk.SurfaceKHR,
) !DeviceCandidate {
    const pdevs = try instance.enumeratePhysicalDevicesAlloc(allocator);
    defer allocator.free(pdevs);

    for (pdevs) |pdev| {
        if (try checkSuitable(instance, pdev, allocator, surface)) |candidate| {
            return candidate;
        }
    }

    return error.NoSuitableDevice;
}

fn checkSuitable(
    instance: Instance,
    pdev: vk.PhysicalDevice,
    allocator: Allocator,
    surface: vk.SurfaceKHR,
) !?DeviceCandidate {
    if (!try checkExtensionSupport(instance, pdev, allocator)) {
        return null;
    }

    if (!try checkSurfaceSupport(instance, pdev, surface)) {
        return null;
    }

    if (try allocateQueues(instance, pdev, allocator, surface)) |allocation| {
        const props = instance.getPhysicalDeviceProperties(pdev);
        return DeviceCandidate{
            .pdev = pdev,
            .props = props,
            .queues = allocation,
        };
    }

    return null;
}

fn allocateQueues(instance: Instance, pdev: vk.PhysicalDevice, allocator: Allocator, surface: vk.SurfaceKHR) !?QueueAllocation {
    const families = try instance.getPhysicalDeviceQueueFamilyPropertiesAlloc(pdev, allocator);
    defer allocator.free(families);

    var graphics_family: ?u32 = null;
    var present_family: ?u32 = null;

    for (families, 0..) |properties, i| {
        const family: u32 = @intCast(i);

        if (graphics_family == null and properties.queue_flags.graphics_bit) {
            graphics_family = family;
        }

        if (present_family == null and (try instance.getPhysicalDeviceSurfaceSupportKHR(pdev, family, surface)) == vk.TRUE) {
            present_family = family;
        }
    }

    if (graphics_family != null and present_family != null) {
        return QueueAllocation{
            .graphics_family = graphics_family.?,
            .present_family = present_family.?,
        };
    }

    return null;
}

fn checkSurfaceSupport(instance: Instance, pdev: vk.PhysicalDevice, surface: vk.SurfaceKHR) !bool {
    var format_count: u32 = undefined;
    _ = try instance.getPhysicalDeviceSurfaceFormatsKHR(pdev, surface, &format_count, null);

    var present_mode_count: u32 = undefined;
    _ = try instance.getPhysicalDeviceSurfacePresentModesKHR(pdev, surface, &present_mode_count, null);

    return format_count > 0 and present_mode_count > 0;
}

fn checkExtensionSupport(
    instance: Instance,
    pdev: vk.PhysicalDevice,
    allocator: Allocator,
) !bool {
    const propsv = try instance.enumerateDeviceExtensionPropertiesAlloc(pdev, null, allocator);
    defer allocator.free(propsv);

    for (required_device_extensions) |ext| {
        for (propsv) |props| {
            if (std.mem.eql(u8, std.mem.span(ext), std.mem.sliceTo(&props.extension_name, 0))) {
                break;
            }
        } else {
            return false;
        }
    }

    return true;
}

fn print_debug_message(callback_data: *const vk.DebugUtilsMessengerCallbackDataEXT) void {
    std.debug.print("vulkan: debug message [id: {s} ({x:8})] {s}\n", .{
        if (callback_data.p_message_id_name) |id_name| id_name else "unknown",
        callback_data.message_id_number,
        if (callback_data.p_message) |message| message else "unknown",
    });

    if (callback_data.p_cmd_buf_labels) |cmd_buf_labels| {
        for (cmd_buf_labels[0..callback_data.cmd_buf_label_count]) |cmd_buf_label| {
            std.debug.print("- command buffer label: '{s}'", .{cmd_buf_label.p_label_name});
        }
    }

    // for (auto& command_buffer_label : std::span(callback_data->pCmdBufLabels, callback_data->cmdBufLabelCount))
    // {
    //     const char* label = command_buffer_label.pLabelName;
    //     log_info(*root, "- command buffer label: '{}'", label ? label : "unnamed");
    // }

    // for (auto& object_name_info : std::span(callback_data->pObjects, callback_data->objectCount))
    // {
    //     const char* label = object_name_info.pObjectName;
    //     log_info(*root, "- object '{}', type = {}, handle = {:#018x}", label ? label : "unnamed",
    //              vk_to_string(object_name_info.objectType), object_name_info.objectHandle);
    // }
}

fn debug_message_callback(severity: vk.DebugUtilsMessageSeverityFlagsEXT, _: vk.DebugUtilsMessageTypeFlagsEXT, callback_data: *const vk.DebugUtilsMessengerCallbackDataEXT, _: *anyopaque) callconv(.C) vk.Bool32 {
    const ID_LoaderMessage: i32 = 0x0000000;
    const ID_UNASSIGNED_BestPractices_vkCreateDevice_specialuse_extension_glemulation: i32 =
        -0x703c3ecb; // CreateDevice(): Attempting to enable extension VK_EXT_primitive_topology_list_restart, but
    // this extension is intended to support OpenGL and/or OpenGL ES emulation layers, and
    // applications ported from those APIs, by adding functionality specific to those APIs and it
    // is strongly recommended that it be otherwise avoided.
    const ID_UNASSIGNED_BestPractices_vkAllocateMemory_small_allocation: i32 =
        -0x23e75295; // vkAllocateMemory(): Allocating a VkDeviceMemory of size 131072. This is a very small
    // allocation (current threshold is 262144 bytes). You should make large allocations and
    // sub-allocate from one large VkDeviceMemory.
    const ID_UNASSIGNED_BestPractices_vkBindMemory_small_dedicated_allocation: i32 =
        -0x4c2bcb95; // vkBindImageMemory(): Trying to bind VkImage 0xb9b24e0000000113[] to a memory block which is
    // fully consumed by the image. The required size of the allocation is 131072, but smaller
    // images like this should be sub-allocated from larger memory blocks. (Current threshold is
    // 1048576 bytes.)
    const ID_UNASSIGNED_BestPractices_pipeline_stage_flags: i32 =
        0x48a09f6c; // You are using VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT_KHR when vkCmdResetEvent2 is called
    const ID_UNASSIGNED_BestPractices_CreatePipelines_AvoidPrimitiveRestart: i32 =
        0x4d6711e7; // [AMD] Performance warning: Use of primitive restart is not recommended
    const ID_UNASSIGNED_BestPractices_vkImage_DontUseStorageRenderTargets: i32 =
        -0x33200141; // [AMD] Performance warning: image 'Lighting' is created as a render target with
    // VK_IMAGE_USAGE_STORAGE_BIT. Using a VK_IMAGE_USAGE_STORAGE_BIT is not recommended with color
    // and depth targets
    const ID_UNASSIGNED_BestPractices_CreateDevice_PageableDeviceLocalMemory: i32 =
        0x2e99adca; // [NVIDIA] vkCreateDevice() called without pageable device local memory. Use
    // pageableDeviceLocalMemory from VK_EXT_pageable_device_local_memory when it is available.
    const ID_UNASSIGNED_BestPractices_AllocateMemory_SetPriority: i32 =
        0x61f61757; // [NVIDIA] Use VkMemoryPriorityAllocateInfoEXT to provide the operating system information on
    // the allocations that should stay in video memory and which should be demoted first when video
    // memory is limited. The highest priority should be given to GPU-written resources like color
    // attachments, depth attachments, storage images, and buffers written from the GPU.
    const ID_UNASSIGNED_BestPractices_CreatePipelineLayout_SeparateSampler: i32 =
        0x362cd642; // [NVIDIA] Consider using combined image samplers instead of separate samplers for marginally
    // better performance.
    const ID_UNASSIGNED_BestPractices_Zcull_LessGreaterRatio: i32 =
        -0xa56a353; // [NVIDIA] Depth attachment VkImage 0xd22318000000014b[Tile Depth Max] is primarily rendered
    // with depth compare op LESS, but some draws use GREATER. Z-cull is disabled for the least used
    // direction, which harms depth testing performance. The Z-cull direction can be reset by
    // clearing the depth attachment, transitioning from VK_IMAGE_LAYOUT_UNDEFINED, using
    // VK_ATTACHMENT_LOAD_OP_DONT_CARE, or using VK_ATTACHMENT_STORE_OP_DONT_CARE.
    const ID_UNASSIGNED_BestPractices_AllocateMemory_ReuseAllocations: i32 =
        0x6e57f7a6; // [NVIDIA] Reuse memory allocations instead of releasing and reallocating. A memory allocation
    // has just been released, and it could have been reused in place of this allocation.

    const ignored_ids = [_]i32{
        ID_LoaderMessage,
        ID_UNASSIGNED_BestPractices_vkCreateDevice_specialuse_extension_glemulation,
        ID_UNASSIGNED_BestPractices_vkAllocateMemory_small_allocation,
        ID_UNASSIGNED_BestPractices_vkBindMemory_small_dedicated_allocation,
        ID_UNASSIGNED_BestPractices_pipeline_stage_flags,
        ID_UNASSIGNED_BestPractices_CreatePipelines_AvoidPrimitiveRestart,
        ID_UNASSIGNED_BestPractices_vkImage_DontUseStorageRenderTargets,
        ID_UNASSIGNED_BestPractices_CreateDevice_PageableDeviceLocalMemory,
        ID_UNASSIGNED_BestPractices_AllocateMemory_SetPriority,
        ID_UNASSIGNED_BestPractices_CreatePipelineLayout_SeparateSampler,
        ID_UNASSIGNED_BestPractices_Zcull_LessGreaterRatio,
        ID_UNASSIGNED_BestPractices_AllocateMemory_ReuseAllocations,
    };

    var ignore_message = false;
    for (ignored_ids) |ignored_id| {
        if (ignored_id == callback_data.message_id_number) {
            ignore_message = true;
        }
    }

    if (!ignore_message) {
        print_debug_message(callback_data);
    }

    // const ignore_assert = ignore_message or severity < vk.WARNING_BIT_EXT;
    _ = severity;
    const ignore_assert = ignore_message;
    std.debug.assert(ignore_assert);

    const exit_on_assert = false;
    if (!ignore_assert and exit_on_assert) {
        unreachable;
    }

    return vk.FALSE;
}
