#include <metal_stdlib>
#include <metal_atomic>
using namespace metal;

struct LatticeMetalNode {
    float2 worldPosition;
    float tenneyHeight;
    float4 color;
    uint nodeID;
    uint flags;
    float complexity;
    float octaveOffset;
};

struct LatticeMetalLink {
    float2 start;
    float2 end;
    float4 color;
    float width;
    float3 pad;
};

struct LatticeMetalUniforms {
    float2 viewportSize;
    float2 translation;
    float scale;
    float baseRadius;
    float time;
    float audioAmplitude;
    float audioPhase;
    uint debugFlags;
    float linkAlpha;
    float hoverLift;
};

struct LatticeMetalPickRequest {
    float2 point;
    uint kind;
    uint token;
};

struct LatticeMetalPickResult {
    uint nodeID;
    uint distanceSquared;
    uint kind;
    uint token;
};

struct PuckVertexOut {
    float4 position [[position]];
    float2 local;
    float4 color;
    float tenneyHeight;
    uint flags;
    uint nodeID;
};

struct LinkVertexOut {
    float4 position [[position]];
    float4 color;
};

float hash11(float p) {
    float x = fract(p * 0.1031);
    x *= x + 33.33;
    x *= x + x;
    return fract(x);
}

kernel void cullNodes(
    device const LatticeMetalNode *nodes [[buffer(0)]],
    device uint *visibleIndices [[buffer(1)]],
    device atomic_uint *visibleCount [[buffer(2)]],
    device float4 *screenNodes [[buffer(3)]],
    constant uint &nodeCount [[buffer(4)]],
    constant LatticeMetalUniforms &uniforms [[buffer(5)]],
    uint id [[thread_position_in_grid]]
) {
    if (id >= nodeCount) { return; }
    LatticeMetalNode node = nodes[id];
    float2 screen = node.worldPosition * uniforms.scale + uniforms.translation;
    screen.y += -node.octaveOffset * 0.65;

    float radius = max(8.0, uniforms.baseRadius + 18.0 / sqrt(max(1.0, node.tenneyHeight)));
    screenNodes[id] = float4(screen, radius, 0.0);

    float2 minPoint = screen - radius;
    float2 maxPoint = screen + radius;
    if (maxPoint.x < 0.0 || minPoint.x > uniforms.viewportSize.x || maxPoint.y < 0.0 || minPoint.y > uniforms.viewportSize.y) {
        return;
    }

    uint index = atomic_fetch_add_explicit(visibleCount, 1, memory_order_relaxed);
    visibleIndices[index] = id;
}

kernel void buildIndirectArgs(
    device const atomic_uint *visibleCount [[buffer(0)]],
    device MTLDrawIndexedPrimitivesIndirectArguments *args [[buffer(1)]],
    constant uint &indexCount [[buffer(2)]],
    uint tid [[thread_position_in_grid]]
) {
    if (tid > 0) { return; }
    uint count = atomic_load_explicit(visibleCount, memory_order_relaxed);
    args->indexCount = indexCount;
    args->instanceCount = count;
    args->indexStart = 0;
    args->baseVertex = 0;
    args->baseInstance = 0;
}

kernel void pickNodes(
    device const uint *visibleIndices [[buffer(0)]],
    device const atomic_uint *visibleCount [[buffer(1)]],
    device const float4 *screenNodes [[buffer(2)]],
    device const LatticeMetalNode *nodes [[buffer(3)]],
    constant LatticeMetalPickRequest &request [[buffer(4)]],
    device LatticeMetalPickResult *result [[buffer(5)]],
    uint id [[thread_position_in_grid]]
) {
    uint count = atomic_load_explicit(visibleCount, memory_order_relaxed);
    if (id >= count) { return; }

    uint nodeIndex = visibleIndices[id];
    float4 screen = screenNodes[nodeIndex];
    float2 delta = request.point - screen.xy;
    float dist2 = dot(delta, delta);
    float radius = screen.z;
    if (dist2 > radius * radius) { return; }

    uint dist = (uint)min(dist2, 4.294e9);
    uint prev = atomic_load_explicit((device atomic_uint *)&result->distanceSquared, memory_order_relaxed);
    while (dist < prev) {
        if (atomic_compare_exchange_weak_explicit((device atomic_uint *)&result->distanceSquared, &prev, dist, memory_order_relaxed, memory_order_relaxed)) {
            result->nodeID = nodes[nodeIndex].nodeID;
            result->kind = request.kind;
            result->token = request.token;
            break;
        }
    }
}

vertex PuckVertexOut puckVertex(
    uint vid [[vertex_id]],
    uint iid [[instance_id]],
    const device float2 *quad [[buffer(0)]],
    const device LatticeMetalNode *nodes [[buffer(1)]],
    const device uint *visibleIndices [[buffer(2)]],
    constant LatticeMetalUniforms &uniforms [[buffer(3)]]
) {
    PuckVertexOut out;
    uint nodeIndex = visibleIndices[iid];
    LatticeMetalNode node = nodes[nodeIndex];
    float2 screen = node.worldPosition * uniforms.scale + uniforms.translation;
    screen.y += -node.octaveOffset * 0.65;

    float radius = max(8.0, uniforms.baseRadius + 18.0 / sqrt(max(1.0, node.tenneyHeight)));
    float2 local = quad[vid];
    float2 pos = screen + local * radius * 2.0;

    float2 ndc = float2(
        (pos.x / max(1.0, uniforms.viewportSize.x)) * 2.0 - 1.0,
        1.0 - (pos.y / max(1.0, uniforms.viewportSize.y)) * 2.0
    );

    out.position = float4(ndc, 0.0, 1.0);
    out.local = local * 2.0;
    out.color = node.color;
    out.tenneyHeight = node.tenneyHeight;
    out.flags = node.flags;
    out.nodeID = node.nodeID;
    return out;
}

fragment float4 puckFragment(
    PuckVertexOut in [[stage_in]],
    constant LatticeMetalUniforms &uniforms [[buffer(0)]],
    const device LatticeMetalNode *nodes [[buffer(1)]],
    const device uint *visibleIndices [[buffer(2)]]
) {
    float r = length(in.local);
    if (r > 1.0) {
        discard_fragment();
    }

    float z = sqrt(max(0.0, 1.0 - r * r));
    float3 normal = normalize(float3(in.local.x, -in.local.y, z));

    float3 lightDir = normalize(float3(-0.4, 0.6, 0.8));
    float3 viewDir = float3(0.0, 0.0, 1.0);
    float ndl = max(0.0, dot(normal, lightDir));
    float fresnel = pow(1.0 - max(0.0, dot(normal, viewDir)), 3.0);

    float roughness = 0.12 + 0.25 * clamp(in.tenneyHeight / 64.0, 0.0, 1.0);
    float sparkle = hash11((float)in.nodeID + in.local.x * 12.7 + in.local.y * 9.3);
    float spec = pow(max(0.0, dot(reflect(-lightDir, normal), viewDir)), 48.0 - roughness * 20.0);
    spec *= mix(0.6, 1.1, sparkle);

    bool isSustaining = (in.flags & 0x4u) != 0u;
    if (isSustaining) {
        float pulse = 0.5 + 0.5 * sin(uniforms.time * 4.0 + uniforms.audioPhase * 1.2);
        spec *= 1.0 + pulse * uniforms.audioAmplitude * 0.6;
    }

    float3 baseColor = in.color.rgb;
    float depth = mix(0.94, 0.65, r * r);
    float3 glass = baseColor * depth + fresnel * float3(1.0);

    bool isHover = (in.flags & 0x1u) != 0u;
    bool isSelected = (in.flags & 0x2u) != 0u;

    float ringWidth = 0.06;
    float ring = smoothstep(1.0, 1.0 - ringWidth, r);
    float ringStrength = 0.0;
    if (isHover) {
        ringStrength = max(ringStrength, 0.55);
    }
    if (isSelected) {
        ringStrength = max(ringStrength, 0.85);
    }

    float3 ringColor = mix(baseColor, float3(1.0), 0.6);
    if ((uniforms.debugFlags & 0x2u) != 0u) {
        ringStrength = 1.0;
        ringColor = float3(0.15, 0.95, 0.25);
    }
    float3 finalColor = glass + ringColor * ringStrength * ring;
    float alpha = in.color.a * (0.55 + 0.35 * ndl);

    float specular = spec * (0.4 + 0.6 * ndl);
    finalColor += specular;

    if ((uniforms.debugFlags & 0x1u) != 0u) {
        float idHash = fract((float)in.nodeID * 0.00037);
        finalColor = mix(finalColor, float3(idHash, 1.0 - idHash, 0.6), 0.6);
    }

    return float4(finalColor, alpha);
}

vertex LinkVertexOut linkVertex(
    uint vid [[vertex_id]],
    uint iid [[instance_id]],
    const device float2 *quad [[buffer(0)]],
    const device LatticeMetalLink *links [[buffer(1)]],
    constant LatticeMetalUniforms &uniforms [[buffer(2)]]
) {
    LinkVertexOut out;
    LatticeMetalLink link = links[iid];

    float2 a = link.start * uniforms.scale + uniforms.translation;
    float2 b = link.end * uniforms.scale + uniforms.translation;
    float2 dir = normalize(b - a);
    float2 normal = float2(-dir.y, dir.x);

    float halfWidth = link.width * 0.5;
    float2 local = quad[vid];
    float2 pos = mix(a, b, (local.y + 1.0) * 0.5) + normal * local.x * halfWidth;

    float2 ndc = float2(
        (pos.x / max(1.0, uniforms.viewportSize.x)) * 2.0 - 1.0,
        1.0 - (pos.y / max(1.0, uniforms.viewportSize.y)) * 2.0
    );

    out.position = float4(ndc, 0.0, 1.0);
    out.color = link.color;
    return out;
}

fragment float4 linkFragment(LinkVertexOut in [[stage_in]],
                             constant LatticeMetalUniforms &uniforms [[buffer(0)]]) {
    float alpha = in.color.a * uniforms.linkAlpha;
    if ((uniforms.debugFlags & 0x4u) != 0u) {
        return float4(float3(1.0 - uniforms.linkAlpha, uniforms.linkAlpha, 0.25), 1.0);
    }
    return float4(in.color.rgb, alpha);
}
