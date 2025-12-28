
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

