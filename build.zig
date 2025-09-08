const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const exe = b.addExecutable(.{
        .name = "p1e",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const default_bios_path = b.dependency("bios", .{}).path("SCPH1001.bin");
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
        const vulkan = b.dependency("vulkan_zig", .{
            .registry = registry.path("registry/vk.xml"),
        }).module("vulkan-zig");

        exe.root_module.addImport("vulkan", vulkan);

        exe.linkLibC();
        exe.linkSystemLibrary("glfw");

        compile_and_embed_hlsl_shader(b, exe.root_module, "./src/renderer/shaders/triangle.vert.hlsl", .Vertex, "triangle_vs") catch unreachable;
        compile_and_embed_hlsl_shader(b, exe.root_module, "./src/renderer/shaders/triangle.frag.hlsl", .Fragment, "triangle_fs") catch unreachable;
        compile_and_embed_hlsl_shader(b, exe.root_module, "./src/renderer/shaders/poly.vert.hlsl", .Vertex, "poly_vs") catch unreachable;
        compile_and_embed_hlsl_shader(b, exe.root_module, "./src/renderer/shaders/poly.frag.hlsl", .Fragment, "poly_fs") catch unreachable;
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
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    b.installArtifact(test_a);

    const test_cmd = b.addRunArtifact(test_a);
    test_cmd.step.dependOn(b.getInstallStep());

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&test_cmd.step);
}

const ShaderStage = enum {
    Vertex,
    Fragment,
};

fn compile_and_embed_hlsl_shader(b: *std.Build, module: *std.Build.Module, hlsl_path: [:0]const u8, shader_stage: ShaderStage, import_name: [:0]const u8) !void {
    const stage_string = switch (shader_stage) {
        ShaderStage.Vertex => "-fshader-stage=vert",
        ShaderStage.Fragment => "-fshader-stage=frag",
    };

    const cmd = b.addSystemCommand(&.{ "glslc", "--target-env=vulkan1.4", stage_string, "-o" });

    const spv_path = try std.mem.concatWithSentinel(b.allocator, u8, &[_][]const u8{ hlsl_path, ".spv" }, 0);
    defer b.allocator.free(spv_path);

    const vert_spv = cmd.addOutputFileArg(spv_path);
    cmd.addFileArg(b.path(hlsl_path));
    module.addAnonymousImport(import_name, .{ .root_source_file = vert_spv });
}
