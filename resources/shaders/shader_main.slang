struct VSInput {
    float3 pos;
    float3 normal;
    float2 texture_coord;
}

struct VSOutput {
    float4 pos: SV_Position;
    float3 normal;
    float2 texture_coord;
};

struct PushConstantBlock {
    float4x4 mvp;    
};

// NOTE: Descriptor sets are ranged from the least to the most specific;
// because updates on one would affect sets going after it.
[[vk::binding(0, 0)]]
Sampler2D diffuse;

[[vk::push_constant]] // mvp mat
ConstantBuffer<PushConstantBlock> push_constant;

[shader("vertex")]
VSOutput vertMain(VSInput input)
{
    VSOutput output;
    output.pos = mul(push_constant.mvp, float4(input.pos, 1.0));
    output.normal = input.normal;
    output.texture_coord = input.texture_coord;
    return output;
}

[shader("fragment")]
float4 fragMain(VSOutput input) : SV_Target
{
    float4 diffuse_sample = diffuse.Sample(input.texture_coord);
    // float4 specular_sample = specular.Sample(input.texture_coord);
    // float4 ambient_sample = ambient.Sample(input.texture_coord);
    // float4 normal_sample = normal.Sample(input.texture_coord);
    return diffuse_sample;
    // NOTE: TEMP
    // return float4(1, 1, 0, 1);
}
