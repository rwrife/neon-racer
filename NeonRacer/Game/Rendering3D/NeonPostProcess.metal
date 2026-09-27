#include <metal_stdlib>
using namespace metal;

struct NeonPostVertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex NeonPostVertexOut neonPostProcessVertex(uint vertexID [[vertex_id]]) {
    float2 positions[4] = {
        float2(-1.0, -1.0),
        float2( 1.0, -1.0),
        float2(-1.0,  1.0),
        float2( 1.0,  1.0)
    };
    // Metal's render target UV origin is at the top; NDC's lower vertices sample its bottom.
    float2 uvs[4] = {
        float2(0.0, 1.0),
        float2(1.0, 1.0),
        float2(0.0, 0.0),
        float2(1.0, 0.0)
    };
    NeonPostVertexOut out;
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.uv = uvs[vertexID];
    return out;
}

static inline float neonHash(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453123);
}

fragment half4 neonPostProcessFragment(
    NeonPostVertexOut in [[stage_in]],
    texture2d<half, access::sample> colorSampler [[texture(0)]]
) {
    constexpr sampler linearSampler(coord::normalized, address::clamp_to_edge, filter::linear);
    float2 uv = in.uv;
    float2 center = uv - 0.5;
    float edge = smoothstep(0.18, 0.78, length(center));
    float split = 0.0008 + edge * 0.0018;

    half4 base = colorSampler.sample(linearSampler, uv);
    half red = colorSampler.sample(linearSampler, uv + float2(split, 0.0)).r;
    half blue = colorSampler.sample(linearSampler, uv - float2(split, 0.0)).b;
    half3 color = half3(red, base.g, blue);

    float scan = sin(uv.y * 980.0);
    float scanMask = 1.0 - (scan * 0.5 + 0.5) * 0.045;
    float grain = (neonHash(uv * float2(850.0, 480.0)) - 0.5) * 0.018;
    float horizon = exp(-abs(uv.y - 0.49) * 15.0) * smoothstep(0.08, 0.85, 1.0 - abs(uv.x - 0.5) * 2.0) * 0.11;
    float vignette = smoothstep(0.94, 0.28, dot(center, center) * 1.35);

    color *= half(scanMask * max(vignette, 0.55));
    color += half3(0.04, 0.0, 0.08) * half(edge);
    color += half3(1.0, 0.18, 0.45) * half(horizon);
    color += half3(grain);
    return half4(saturate(color), base.a);
}
