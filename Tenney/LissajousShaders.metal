
//
//  LissajousShaders.metal
//  Tenney
//
//  Created by Sebastian Suarez-Solis on 10/7/25.
//

#include <metal_stdlib>
using namespace metal;


// ---- Shared structs ---------------------------------------------------------
struct VSIn {
    float2 pos;
    float4 color;
};

struct Uniforms {
    float2 scale;
    float2 pan;
    float  alpha;
    float  pointSize;   // used in dot mode
    float  ribbonWidth;
    float  globalAlpha;
    float  edgeAA;
    float  _pad;
    float4 coreColor;
    float4 sheenColor;
};

// ---- Line / Point pass ------------------------------------------------------
struct Varyings {
    float4 position [[position]];
    float4 color;
    float  psize [[point_size]];
};

vertex Varyings lissa_vtx(uint vid [[vertex_id]],
                          const device VSIn* vtx [[buffer(0)]],
                          constant Uniforms& U   [[buffer(1)]]) {
    Varyings o;
    float2 p = vtx[vid].pos * U.scale + U.pan;
    o.position = float4(p, 0.0, 1.0);
    o.color = float4(vtx[vid].color.rgb, vtx[vid].color.a * U.alpha);
    o.psize = max(1.0f, U.pointSize);
    return o;
}

fragment float4 lissa_frag(Varyings in [[stage_in]]) {
    return in.color; // premultiplied not required; blending configured in Swift
}

// ---- Ribbon pass -----------------------------------------------------------
struct RibbonVSIn {
    float2 pos;
    float2 normal;
    float  side;
    float  u;
};

struct RibbonVaryings {
    float4 position [[position]];
    float  side;
    float  u;
};

vertex RibbonVaryings lissa_ribbon_vtx(uint vid [[vertex_id]],
                                       const device RibbonVSIn* vtx [[buffer(0)]],
                                       constant Uniforms& U        [[buffer(1)]]) {
    RibbonVaryings o;
    float2 p = vtx[vid].pos;
    float2 n = vtx[vid].normal;
    float s  = vtx[vid].side;
    float width = max(0.1f, U.ribbonWidth);
    float2 offset = n * (0.5f * width * s);
    float2 world = (p + offset) * U.scale + U.pan;
    o.position = float4(world, 0.0, 1.0);
    o.side = s;
    o.u = vtx[vid].u;
    return o;
}

inline float sat(float x) { return clamp(x, 0.0f, 1.0f); }

fragment float4 lissa_ribbon_frag(RibbonVaryings in [[stage_in]],
                                  constant Uniforms& U [[buffer(1)]]) {

    float t = sat(in.u);            // 0..1 across ribbon width
    float a = fabs(in.side);        // 0 at center, 1 at edge

    // --- Analytic AA (critical for single-sample persistence path)
    float w = max(1e-4f, fwidth(a) * max(0.5f, U.edgeAA));
    float coverage = 1.0f - smoothstep(1.0f - w, 1.0f + w, a);

    // --- Thickness profile (center thicker, edges thinner)
    float core = pow(1.0f - a, 1.6f);
    float rim  = pow(a, 2.2f);

    // --- Two-tone tint across width
    float tone = smoothstep(0.0f, 1.0f, t);
    float3 tint = mix(U.coreColor.rgb, U.sheenColor.rgb, tone);

    // --- Specular ridge(s) for “glass” read
    float ridge1 = exp2(-pow((t - 0.25f) / 0.12f, 2.0f));
    float ridge2 = exp2(-pow((t - 0.78f) / 0.18f, 2.0f));
    float spec   = 0.55f * ridge1 + 0.25f * ridge2;

    // --- Final color (body + sheen)
    float3 rgb = tint * (0.30f + 0.70f * core) + U.sheenColor.rgb * spec;

    // --- Alpha: more transparent at edges, denser at center
    float alpha = U.globalAlpha * coverage * (0.10f + 0.90f * core);

    // slight rim lift (helps “glass edge” without turning neon)
    rgb += U.sheenColor.rgb * (0.06f * rim);

    // premultiplied output
    return float4(rgb * alpha, alpha);
}

fragment float4 lissa_ribbon_glow_frag(RibbonVaryings in [[stage_in]],
                                       constant Uniforms& U [[buffer(1)]]) {

    float t = sat(in.u);
    float a = fabs(in.side);

    float w = max(1e-4f, fwidth(a) * max(0.5f, U.edgeAA));
    float coverage = 1.0f - smoothstep(1.0f - w, 1.0f + w, a);

    float core = pow(1.0f - a, 1.35f);

    // gentle, wide halo — mostly sheen tint
    float ridge = exp2(-pow((t - 0.35f) / 0.22f, 2.0f));
    float3 rgb = U.sheenColor.rgb * (0.22f + 0.55f * ridge) * (0.35f + 0.65f * core);

    float alpha = U.globalAlpha * coverage * (0.10f + 0.90f * core);

    return float4(rgb * alpha, alpha);
}

// ---- Fullscreen quad for persistence / blit ---------------------------------
struct QuadVSOut { float4 pos [[position]]; float2 uv; };

vertex QuadVSOut quad_vtx(uint vid [[vertex_id]]) {
    // triangle strip: ( -1,-1 ) ( 1,-1 ) ( -1,1 ) ( 1,1 )
    const float2 pos[4] = { {-1,-1}, {1,-1}, {-1,1}, {1,1} };
    const float2 uv[4]  = { {0,0},   {1,0},  {0,1},  {1,1} };
    QuadVSOut o;
    o.pos = float4(pos[vid], 0, 1);
    o.uv  = uv[vid];
    return o;
}

fragment float4 decay_frag(QuadVSOut in [[stage_in]],
                           texture2d<float> prevTex [[texture(0)]],
                           constant float& decay     [[buffer(0)]],
                           sampler s                 [[sampler(0)]]) {
    float4 c = prevTex.sample(s, in.uv);
    c *= decay; // exponential fade
    return c;
}

fragment float4 blit_frag(QuadVSOut in [[stage_in]],
                          texture2d<float> tex [[texture(0)]],
                          sampler s            [[sampler(0)]]) {
    return tex.sample(s, in.uv);
}
