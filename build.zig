const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const exe = b.addExecutable(.{
        .name = "psxemu",
        .root_source_file = b.path("src/main.zig"),
        .optimize = optimize,
        .target = target,
    });

    const default_bios_path = b.path("external/bios/SCPH1001.bin");
    const bios_path = b.option(std.Build.LazyPath, "bios_path", "Path to SCPH1001.BIN") orelse default_bios_path;

    exe.root_module.addAnonymousImport("bios", .{ .root_source_file = bios_path });

    const enable_vulkan_backend = b.option(bool, "vulkan", "Enable Vulkan renderer support") orelse false;
    const enable_tracy = b.option(bool, "tracy", "Enable Tracy support") orelse false;
    const tracy_callstack = b.option(bool, "tracy-callstack", "Include callstack information with Tracy data. Does nothing if -Dtracy is not provided") orelse false;
    const no_bin = b.option(bool, "no-bin", "skip emitting binary") orelse false;

    const exe_options = b.addOptions();
    exe_options.addOption(bool, "enable_vulkan_backend", enable_vulkan_backend);
    exe_options.addOption(bool, "enable_tracy", enable_tracy);
    exe_options.addOption(bool, "enable_tracy_callstack", tracy_callstack);
    exe.root_module.addOptions("build_options", exe_options);

    if (enable_vulkan_backend) {
        const registry = b.dependency("vulkan_headers", .{});
        const vulkan_zig = b.dependency("vulkan_zig", .{});

        const vulkan_zig_generator = vulkan_zig.artifact("vulkan-zig-generator");
        const vk_generate_cmd = b.addRunArtifact(vulkan_zig_generator);

        const registry_path = registry.path("registry/vk.xml");
        vk_generate_cmd.addFileArg(registry_path);

        exe.linkLibC();
        exe.linkSystemLibrary("glfw");

        exe.root_module.addAnonymousImport("vulkan", .{
            .root_source_file = vk_generate_cmd.addOutputFileArg("vk.zig"),
        });

        const vert_cmd = b.addSystemCommand(&.{ "glslc", "--target-env=vulkan1.3", "-fshader-stage=vert", "-o" });
        const vert_spv = vert_cmd.addOutputFileArg("vert.spv");
        vert_cmd.addFileArg(b.path("./src/renderer/shaders/triangle.vert.hlsl")); // FIXME
        exe.root_module.addAnonymousImport("vertex_shader", .{ .root_source_file = vert_spv });

        const frag_cmd = b.addSystemCommand(&.{ "glslc", "--target-env=vulkan1.3", "-fshader-stage=frag", "-o" });
        const frag_spv = frag_cmd.addOutputFileArg("frag.spv");
        frag_cmd.addFileArg(b.path("./src/renderer/shaders/triangle.frag.hlsl")); // FIXME
        exe.root_module.addAnonymousImport("fragment_shader", .{ .root_source_file = frag_spv });
    }

    if (enable_tracy) {
        const tracy_path = "external/tracy";
        const client_cpp = "external/tracy/public/TracyClient.cpp";
        const tracy_c_flags: []const []const u8 = &[_][]const u8{ "-DTRACY_ENABLE=1", "-fno-sanitize=undefined" };

        exe.root_module.addIncludePath(b.path(tracy_path));
        exe.root_module.addCSourceFile(.{ .file = b.path(client_cpp), .flags = tracy_c_flags });

        exe.linkSystemLibrary("c++");
        exe.linkLibC();
    }

    if (no_bin) {
        b.getInstallStep().dependOn(&exe.step);
    } else {
        b.installArtifact(exe);
    }

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the program");
    run_step.dependOn(&run_cmd.step);

    // Test
    const test_a = b.addTest(.{
        .name = "test",
        .root_source_file = b.path("src/test.zig"),
        .optimize = optimize,
    });

    b.installArtifact(test_a);

    const test_cmd = b.addRunArtifact(test_a);
    test_cmd.step.dependOn(b.getInstallStep());

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&test_cmd.step);
}
