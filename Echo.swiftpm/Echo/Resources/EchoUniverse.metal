#include <metal_stdlib>
using namespace metal;
struct Segment { float4 a; float4 b; };
struct Uniforms {
    float4x4 transform;
    float2 viewport;
    float time, level, phase, intensity, motion, padding;
};
struct Raster { float4 position [[position]]; float side; float brightness; };
vertex Raster echoUniverseVertex(uint vertexID [[vertex_id]], uint instanceID [[instance_id]],
                                device const Segment *segments [[buffer(0)]], constant Uniforms &u [[buffer(1)]]) {
    Segment segment = segments[instanceID];
    float3 a = segment.a.xyz, b = segment.b.xyz;
    float radius = length(a);
    float pulse = u.motion * u.intensity * (u.level * 0.025 + (u.phase == 2 ? sin(u.time * 1.5 + radius * 7) * 0.004 : 0));
    float4 pa = u.transform * float4(a * (1 + pulse), 1);
    float4 pb = u.transform * float4(b * (1 + pulse), 1);
    float2 direction = (pb.xy / pb.w - pa.xy / pa.w) * u.viewport;
    float2 normal = float2(-direction.y, direction.x) / max(length(direction), 0.0001);
    const float2 corners[6] = {float2(0,-1),float2(1,-1),float2(0,1),float2(0,1),float2(1,-1),float2(1,1)};
    float2 corner = corners[vertexID];
    float4 p = mix(pa, pb, corner.x);
    p.xy += normal * corner.y * 2.8 / u.viewport * p.w;
    float shimmer = 0.88 + 0.12 * sin(u.time * 0.65 + segment.b.w * 4) * u.motion;
    float wave = u.phase == 4 ? pow(max(0.0, sin(radius * 8 - u.time * 4)), 12.0) * 0.25 * u.motion : 0;
    float success = u.phase == 5 ? 0.18 : 0;
    Raster out; out.position = p; out.side = corner.y;
    out.brightness = segment.a.w * shimmer * (1 + wave + success + u.level * 0.15) * clamp(4.5 / p.w, 0.5, 1.3);
    return out;
}
fragment float4 echoUniverseFragment(Raster in [[stage_in]]) {
    float core = exp(-in.side * in.side * 55.0);
    float halo = exp(-in.side * in.side * 5.0) * 0.10;
    return float4(float3(1.0, 0.53, 0.17), (core + halo) * in.brightness * 0.65);
}
