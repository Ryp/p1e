#define VK_BINDING(_set, _binding) [[vk::binding(_binding, _set)]]

VK_BINDING(0, 0) ByteAddressBuffer vertex_buffer;

static const uint vertex_size_bytes = 5 * 4;

float2 pull_position(ByteAddressBuffer byte_buffer, uint vertex_id)
{
    return asfloat(byte_buffer.Load2(vertex_id * vertex_size_bytes + 0));
}

float3 pull_color(ByteAddressBuffer byte_buffer, uint vertex_id)
{
    return asfloat(byte_buffer.Load3(vertex_id * vertex_size_bytes + 2 * 4));
}

struct VS_INPUT
{
    uint vertex_id : SV_VertexID;
};

struct VS_OUTPUT
{
    float4 position_cs : SV_Position;
    float3 color : TEXCOORD0;
};

void main(in VS_INPUT input, out VS_OUTPUT output)
{
    const float2 position = pull_position(vertex_buffer, input.vertex_id);
    const float3 color = pull_color(vertex_buffer, input.vertex_id);

    output.position_cs = float4(position * 2 - 1, 0.0, 1.0);
    output.color = color;
}
