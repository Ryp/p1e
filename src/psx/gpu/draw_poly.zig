const std = @import("std");

const PSXState = @import("../state.zig").PSXState;

const state = @import("state.zig");
const PhatVertex = state.PhatVertex;
const f32_2 = state.f32_2;
const f32_3 = state.f32_3;

const g0 = @import("instructions_g0.zig");
const mmio = @import("mmio.zig");

const pixel_format = @import("pixel_format.zig");
const PackedRGB8 = pixel_format.PackedRGB8;

const VRAMTextureWidth = 1024;
const VRAMTextureHeight = 512;
const stride_y = VRAMTextureWidth; // FIXME

const PhatPackedVertex = struct {
    position: g0.PackedVertexPos,
    color: PackedRGB8,
};

const AABB_f32_2 = struct {
    min: f32_2,
    max: f32_2,
};

pub const u32_2 = @Vector(2, u32);

const AABB_u32_2 = struct {
    min: u32_2,
    max: u32_2,
};

const PolyInstance = struct {
    clut: g0.PackedClut,
    tex_page: g0.PackedTexPage,
};

// NOTE: All Quad/Tri commands have the same initial layout, quad only has an extra vertex at the end.
// For this reason we cast the command bytes to the triangle struct and handle the quad case manually.
pub fn execute(psx: *PSXState, draw_poly: g0.DrawPolyOpCode, command_bytes: []const u8) void {
    const vertex_count: u32 = if (draw_poly.is_quad) 4 else 3;

    var packed_vertices_raw: [4]PhatVertex = undefined;
    const phat_vertices = packed_vertices_raw[0..vertex_count];

    if (draw_poly.is_shaded) {
        if (draw_poly.is_textured) {
            const shaded_textured = std.mem.bytesAsValue(g0.DrawTriangleShadedTextured, command_bytes);
            _ = shaded_textured;

            unreachable;
        } else {
            const PackedVertexOffset = 0;
            const PackedVertexBytes = 8;
            const PackedVertex = packed struct(u64) {
                color: PackedRGB8,
                unused: u8,
                pos: g0.PackedVertexPos,
            };

            for (phat_vertices, 0..vertex_count) |*phat_vertex, vertex_index| {
                const vertex_slice = command_bytes[PackedVertexOffset + vertex_index * PackedVertexBytes ..][0..PackedVertexBytes];
                const v = std.mem.bytesAsValue(PackedVertex, vertex_slice);

                phat_vertex.* = .{
                    .pos = packed_vertex_to_f32_2(v.pos),
                    .color = packed_color_to_f32_3(v.color),
                    .tex = undefined,
                };
            }

            const shaded = std.mem.bytesAsValue(g0.DrawTriangleShaded, command_bytes);
            _ = shaded;

            draw_poly_generic(psx, draw_poly, undefined, phat_vertices);
        }
    } else {
        if (draw_poly.is_textured) {
            const command_textured = std.mem.bytesAsValue(g0.DrawTriangleTextured, command_bytes);

            const PackedVertexOffset = 4;
            const PackedVertexBytes = 8;
            const PackedVertex = packed struct(u64) {
                pos: g0.PackedVertexPos,
                tex: g0.PackedTexCoord,
                unused: u16,
            };

            for (phat_vertices, 0..vertex_count) |*phat_vertex, vertex_index| {
                const vertex_slice = command_bytes[PackedVertexOffset + vertex_index * PackedVertexBytes ..][0..PackedVertexBytes];
                const v = std.mem.bytesAsValue(PackedVertex, vertex_slice);

                phat_vertex.* = .{
                    .pos = packed_vertex_to_f32_2(v.pos),
                    .color = packed_color_to_f32_3(command_textured.color), // FIXME pass color as is instead of interpolating
                    .tex = packed_tex_coord_to_f32_2(v.tex),
                };
            }

            const instance = PolyInstance{
                .clut = command_textured.palette,
                .tex_page = command_textured.tex_page,
            };

            draw_poly_generic(psx, draw_poly, instance, phat_vertices);
        } else {
            const monochrome = std.mem.bytesAsValue(g0.DrawTriangleMonochrome, command_bytes);

            const PackedVertexOffset = 4;
            const PackedVertexBytes = 4;
            const PackedVertex = packed struct(u32) {
                pos: g0.PackedVertexPos,
            };

            for (phat_vertices, 0..vertex_count) |*phat_vertex, vertex_index| {
                const vertex_slice = command_bytes[PackedVertexOffset + vertex_index * PackedVertexBytes ..][0..PackedVertexBytes];
                const v = std.mem.bytesAsValue(PackedVertex, vertex_slice);

                phat_vertex.* = .{
                    .pos = packed_vertex_to_f32_2(v.pos),
                    .color = packed_color_to_f32_3(monochrome.color), // FIXME pass color as is instead of interpolating
                    .tex = undefined,
                };
            }

            draw_poly_generic(psx, draw_poly, undefined, phat_vertices);
        }
    }
}

fn draw_poly_generic(psx: *PSXState, op_code: g0.DrawPolyOpCode, instance: PolyInstance, phat_vertices: []const PhatVertex) void {
    for (0..phat_vertices.len - 2) |triangle_index| {
        const tri_vertices = phat_vertices[triangle_index..][0..3];

        draw_poly_triangle(psx, op_code, instance, tri_vertices.*);
    }

    push_poly_color(psx, op_code, phat_vertices);
}

// FIXME normalization from viewport!
// FIMXE Third channel isn't really needed, or at least not at that time.
// FIXCME can we do float4(float2 , float2) in zig?
fn packed_vertex_to_f32_2(packed_vertex: g0.PackedVertexPos) f32_2 {
    return .{
        @floatFromInt(packed_vertex.x),
        @floatFromInt(packed_vertex.y),
    };
}

fn packed_color_to_f32_3(packed_color: pixel_format.PackedRGB8) f32_3 {
    return f32_3{
        @floatFromInt(packed_color.r),
        @floatFromInt(packed_color.g),
        @floatFromInt(packed_color.b),
    } * @as(f32_3, @splat(1.0 / 255.0));
}

// FIXME not at all tested
fn packed_tex_coord_to_f32_2(packed_tex_coord: g0.PackedTexCoord) f32_2 {
    return .{
        @floatFromInt(packed_tex_coord.x),
        @floatFromInt(packed_tex_coord.y),
    };
}

pub fn push_poly_color(psx: *PSXState, op_code: g0.DrawPolyOpCode, vertices: []const PhatVertex) void {
    const index_count: u32 = if (op_code.is_quad) 6 else 3;
    const backend = &psx.gpu.backend;

    backend.draw_command_buffer[backend.draw_command_offset] = .{
        //.op_code = op_code,
        .index_offset = backend.index_offset,
        .index_count = index_count,
    };

    @memcpy(backend.vertex_buffer[backend.vertex_offset..][0..vertices.len], vertices);

    if (op_code.is_quad) {
        @memcpy(backend.index_buffer[backend.index_offset..][0..index_count], &[_]u32{
            backend.vertex_offset + 0, // 1st triangle
            backend.vertex_offset + 1,
            backend.vertex_offset + 2,
            backend.vertex_offset + 1, // 2nd triangle
            backend.vertex_offset + 2,
            backend.vertex_offset + 3,
        });
    } else {
        @memcpy(backend.index_buffer[backend.index_offset..][0..3], &[_]u32{
            backend.vertex_offset + 0,
            backend.vertex_offset + 1,
            backend.vertex_offset + 2,
        });
    }

    // Update counters at the end
    backend.vertex_offset += @intCast(vertices.len);
    backend.index_offset += index_count;
    backend.draw_command_offset += 1;
}

// FIXME overlap of quads along the diagonal, maybe we're not correctly excluding pixels on the edge
fn draw_poly_triangle(psx: *PSXState, op_code: g0.DrawPolyOpCode, instance: PolyInstance, v: [3]PhatVertex) void {
    const v1 = v[0];
    var v2 = v[1];
    var v3 = v[2];

    // FIXME
    var det_v123 = det2(v2.pos - v1.pos, v3.pos - v1.pos);

    if (det_v123 < 0.0) {
        std.mem.swap(PhatVertex, &v2, &v3);
        det_v123 = -det_v123;
    }

    const v_min_x = @min(v1.pos[0], @min(v2.pos[0], v3.pos[0]));
    const v_min_y = @min(v1.pos[1], @min(v2.pos[1], v3.pos[1]));

    const v_max_x = @max(v1.pos[0], @max(v2.pos[0], v3.pos[0]));
    const v_max_y = @max(v1.pos[1], @max(v2.pos[1], v3.pos[1]));

    const triangle_aabb_f32 = AABB_f32_2{
        .min = .{ v_min_x, v_min_y },
        .max = .{ v_max_x, v_max_y },
    };

    const triangle_aabb_u32 = AABB_u32_2{
        .min = .{
            @intFromFloat(triangle_aabb_f32.min[0]),
            @intFromFloat(triangle_aabb_f32.min[1]),
        },
        .max = .{
            @intFromFloat(triangle_aabb_f32.max[0]),
            @intFromFloat(triangle_aabb_f32.max[1]),
        },
    };

    const vram_typed = std.mem.bytesAsSlice(pixel_format.PackedRGB5A1, psx.gpu.vram);

    for (triangle_aabb_u32.min[1]..triangle_aabb_u32.max[1]) |y| {
        for (triangle_aabb_u32.min[0]..triangle_aabb_u32.max[0]) |x| {
            const pos: f32_2 = .{
                @floatFromInt(x),
                @floatFromInt(y),
            };

            const det_v12 = det2(v2.pos - v1.pos, pos - v1.pos);
            const det_v23 = det2(v3.pos - v2.pos, pos - v2.pos);
            const det_v31 = det2(v1.pos - v3.pos, pos - v3.pos);

            const l1 = det_v23 / det_v123;
            const l2 = det_v31 / det_v123;
            const l3 = det_v12 / det_v123;

            const color = v1.color * @as(f32_3, @splat(l1)) + v2.color * @as(f32_3, @splat(l2)) + v3.color * @as(f32_3, @splat(l3));

            const tex = v1.tex * @as(f32_2, @splat(l1)) + v2.tex * @as(f32_2, @splat(l2)) + v3.tex * @as(f32_2, @splat(l3));

            if (det_v12 >= 0.0 and det_v23 >= 0.0 and det_v31 >= 0.0) {
                var output: pixel_format.PackedRGB5A1 = undefined;
                const vram_output_offset = y * stride_y + x;

                if (op_code.is_textured) {
                    // FIXME
                    std.debug.assert(instance.tex_page.zero_b14_15 == 0);
                    const page_x_offset = @as(u32, instance.tex_page.texture_x_base) * 64;
                    const page_y_offset = @as(u32, instance.tex_page.texture_y_base) * 256;

                    var tx: u32 = @as(u8, @intFromFloat(tex[0]));
                    var ty: u32 = @as(u8, @intFromFloat(tex[1]));

                    std.debug.assert(tx < 256);
                    std.debug.assert(ty < 256);

                    // FIXME
                    tx = (tx & ~psx.gpu.regs.texture_window_x_mask) | (psx.gpu.regs.texture_window_x_offset & psx.gpu.regs.texture_window_x_mask);
                    ty = (ty & ~psx.gpu.regs.texture_window_y_mask) | (psx.gpu.regs.texture_window_y_offset & psx.gpu.regs.texture_window_y_mask);

                    switch (instance.tex_page.texture_page_colors) {
                        ._4bits => {
                            std.debug.assert(instance.clut.zero == 0);
                            const clut_x = @as(u32, instance.clut.x) * 16;
                            const clut_y = @as(u32, instance.clut.y);

                            const clut_slice = vram_typed[clut_y * stride_y + clut_x ..][0..16];

                            const clut_chunk: u16 = @bitCast(vram_typed[page_x_offset + tx / 4 + (page_y_offset + ty) * stride_y]);
                            const clut_index: u4 = @truncate(clut_chunk >> @intCast((tx % 4) * 4));

                            output = clut_slice[clut_index];
                        },
                        ._8bits => {
                            @panic("8Bits Not implemented");
                        },
                        ._15bits => {
                            tx = (tx + page_x_offset);
                            ty = (ty + page_y_offset);

                            output = vram_typed[tx + ty * stride_y];
                        },
                        .Reserved => @panic("Invalid texture page color mode"),
                    }
                } else {
                    output = pixel_format.convert_rgb_f32_to_rgb5a1(color, 0);
                }

                if (output == pixel_format.PackedRGB5A1{ .r = 0, .g = 0, .b = 0, .a = 0 }) {
                    continue;
                } else if (op_code.is_semi_transparent and output.a == 1) {
                    const background = vram_typed[vram_output_offset];

                    // FIXME if not textured, do we get semi_transparency_mode from GPUSTAT?
                    std.debug.assert(op_code.is_textured);

                    vram_typed[vram_output_offset] = compute_alpha_blending(background, output, instance.tex_page.semi_transparency_mode);
                } else {
                    vram_typed[vram_output_offset] = output;
                }
            }
        }
    }
}

// FIXME what happens with alpha?
fn compute_alpha_blending(background: pixel_format.PackedRGB5A1, foreground: pixel_format.PackedRGB5A1, semi_transparency_mode: mmio.MMIO.Packed.SemiTransparency) pixel_format.PackedRGB5A1 {
    return switch (semi_transparency_mode) {
        .B_half_plus_F_half => .{
            .r = (background.r / 2) +| (foreground.r / 2),
            .g = (background.g / 2) +| (foreground.g / 2),
            .b = (background.b / 2) +| (foreground.b / 2),
            .a = foreground.a, // FIXME
        },
        .B_plus_F => @panic("B_plus_F not implemented"),
        .B_minus_F => @panic("B_minus_F not implemented"),
        .B_plus_F_quarter => @panic("B_plus_F_quarter not implemented"),
    };
}

fn det2(p1: f32_2, p2: f32_2) f32 {
    return (p1[0] * p2[1]) - (p1[1] * p2[0]);
}
