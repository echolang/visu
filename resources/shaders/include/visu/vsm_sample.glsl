/**
 * Point-light shadows from the virtual shadow atlas, for the shading passes. The includer binds
 * the page table at storage 4, the light generations at storage 5 and the atlas at storage 6.
 */
#ifndef VISU_VSM_SAMPLE_GLSL
#define VISU_VSM_SAMPLE_GLSL

#include "visu/vsm.glsl"
#include "visu/light_gpu.glsl"

layout(std430, set = 2, binding = 4) readonly buffer VsmPageTable {
    uint u_vsm_table[];
};

layout(std430, set = 2, binding = 5) readonly buffer VsmGenerations {
    uint u_vsm_gens[];
};

layout(std430, set = 2, binding = 6) readonly buffer VsmAtlas {
    float u_vsm_atlas[];
};

// the face-space depth a stored zero-to-one depth stands for
float vsm_linear(float depth, float radius)
{
    float f = max(radius, VSM_NEAR * 2.0);
    float a = f / (f - VSM_NEAR);
    return a * VSM_NEAR / max(a - depth, 1e-6);
}

// how much of light `slot` (at `L`, reach `radius`) reaches `P`: the finest mapped page of the
// level the pixel footprint wants, walking to coarser ones, 3 x 3 filtered; -1 with no page
float vsm_lookup(uint slot, vec3 L, float radius, vec3 P, float footprint, float mipBias)
{
    vec3 d = P - L;
    uint face = vsm_face(d);
    vec3 v = vsm_view(face, d);
    if (v.z <= VSM_NEAR) {
        return 1.0;
    }

    vec2 f = v.xy / v.z;
    uint gen = u_vsm_gens[slot] & VSM_GEN_MASK;
    uint base = slot * VSM_LIGHT_PAGES;
    float missing = -1.0;
    for (uint m = vsm_mip(footprint, v.z, mipBias); m < VSM_MIPS; m++) {
        uvec2 xy = vsm_page_xy(f, m);
        uint entry = u_vsm_table[base + vsm_page_index(face, m, xy)];
        if (entry == VSM_NONE) {
            continue;
        }
        if ((entry >> 16u) != gen) {
            missing = -2.0;
            continue;
        }

        vec4 rect = vsm_page_rect(m, xy);
        ivec2 t = ivec2(floor(vsm_cell_texel(f, rect)));
        uint cell = (entry & 0xFFFFu) * VSM_CELL_TEXELS;
        // a texel of this level, in metres at this depth; the bias is one and a half of them
        float texel = 2.0 * v.z / (VSM_FACE / float(1u << m));
        float receiver = v.z - texel * 1.5;
        float shadow = 0.0;
        for (int x = -1; x <= 1; ++x) {
            for (int y = -1; y <= 1; ++y) {
                ivec2 at = clamp(t + ivec2(x, y), ivec2(0), ivec2(int(VSM_CELL) - 1));
                float stored = u_vsm_atlas[cell + uint(at.y) * VSM_CELL + uint(at.x)];
                shadow += receiver > vsm_linear(stored, radius) ? 1.0 : 0.0;
            }
        }
        // fast math can land a full shadow a hair under zero; the sentinels are -1 and -2
        return clamp(1.0 - shadow / 9.0, 0.0, 1.0);
    }
    return missing;
}

float vsm_visibility(uint slot, vec3 L, float radius, vec3 P, float footprint, float mipBias)
{
    float v = vsm_lookup(slot, L, radius, P, footprint, mipBias);
    return v < -0.5 ? 1.0 : v;
}

// how far the shadow of a light at `L` has faded out towards the shadow distance `limit`:
// 1 is the full shadow, 0 no shadow (and no lookup needed)
float vsm_fade(vec3 L, vec3 eye, float limit)
{
    float d = distance(L, eye);
    return clamp((limit - d) / max(limit * 0.15, 1.0), 0.0, 1.0);
}

// the shadow fade of light `l` seen from `eye` under the pass's `u_vsm` (x 1 when the atlas is
// bound, w the shadow distance): 0 for a light that casts none or with no atlas
float vsm_light_fade(LightGpu l, vec3 eye, vec4 vsm)
{
    return l.source.y > 0.5 && vsm.x > 0.5 ? vsm_fade(l.position_radius.xyz, eye, vsm.w) : 0.0;
}

#endif
