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

// struct GlobalUniformObject {
//     float4x4    view;
//     float4x4    projection;
//     float4x4    padding_1;
//     float4x4    padding_2;
// };

// struct LocalUniformObject {
//     float4 diffuse_color;
//     float4 padding_0;
//     float4 padding_1;
//     float4 padding_2;
// };

struct PushConstantBlock {
    float4x4 mvp;    
};

// set 0 - global
// [[vk::binding(0, 0)]]
// ConstantBuffer<GlobalUniformObject> global_ubo; // view + proj mat

// set 1 - object
// [[vk::binding(0, 1)]]
// ConstantBuffer<LocalUniformObject> object_ubo;

// [[vk::binding(1, 1)]]
// Sampler2D diffuse;
// [[vk::binding(2, 1)]]
// Sampler2D specular;
// [[vk::binding(3, 1)]]
// Sampler2D ambient;
// [[vk::binding(4, 1)]]
// Sampler2D normal;

[[vk::push_constant]]
ConstantBuffer<PushConstantBlock> push_constant; // model mat

// NOTE: TEMP
[shader("vertex")]
VSOutput vertMain(VSInput input)
{
    VSOutput output;
    output.pos = mul(push_constant.mvp, float4(input.pos, 1.0));
    output.texture_coord = input.texture_coord;
    output.normal = input.normal;
    return output;
}

// NOTE: TEMP
[shader("fragment")]
float4 fragMain(VSOutput input) : SV_Target
{
    // float4 diffuse_sample = diffuse.Sample(input.texture_coord);
    // float4 specular_sample = specular.Sample(input.texture_coord);
    // float4 ambient_sample = ambient.Sample(input.texture_coord);
    // float4 normal_sample = normal.Sample(input.texture_coord);
    // return lerp(lerp(lerp(diffuse_sample, specular_sample, 0.2), ambient_sample, 0.2), normal_sample, 0.2);
    return float4(0.0, 1.0, 0.0, 1.0);
}
