struct PS_INPUT
{
    float4 position_cs : SV_Position;
    float3 color : TEXCOORD0;
};

struct PS_OUTPUT
{
    float4 color : SV_Target0;
};

void main(in PS_INPUT input, out PS_OUTPUT output)
{
    output.color = float4(input.color, 1.0);
}
