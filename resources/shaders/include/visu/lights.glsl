/**
 * Clustered point lights: the GPU-resident light table and the per-view cull that
 * visu::graphics::LightCull writes (visible keys sorted by view depth, z-bins over them, and a
 * bitmask per screen tile). A pixel takes the z-bin of its depth, ANDs the matching words of its
 * tile's mask and shades the set bits in ascending order, so the sum is the same every run.
 * Mirrors LightGpu and the LIGHT_* constants of visu::graphics::LightTable / LightCull.
 *
 * The includer binds the storage below and hands the helpers the view's cluster head (x visible
 * count, y tile pixels, z tiles across, w mask words) and z params (x near, y slices per log2
 * metre, z slices, w seconds for the flicker): LightUniforms `u_cluster_head` / `u_cluster_z` in
 * the shading passes, VsmParams in the shadow atlas request.
 */
#ifndef VISU_LIGHTS_GLSL
#define VISU_LIGHTS_GLSL

#include "visu/light_gpu.glsl"

layout(std430, set = 2, binding = 0) readonly buffer LightTableBuffer {
    LightGpu u_lights[];
};

layout(std430, set = 2, binding = 1) readonly buffer LightKeys {
    uint u_light_keys[];
};

layout(std430, set = 2, binding = 2) readonly buffer LightZBins {
    // min then max visible index per slice
    uvec2 u_light_zbins[];
};

layout(std430, set = 2, binding = 3) readonly buffer LightTiles {
    uint u_light_tiles[];
};

// the visible index range [lo, hi] of this pixel's slice; lo > hi when it has none
uvec2 light_range(float viewDepth, vec4 clusterHead, vec4 clusterZ)
{
    if (clusterHead.x < 0.5) {
        return uvec2(1u, 0u);
    }
    uvec2 bin = u_light_zbins[light_zslice(viewDepth, clusterZ)];
    // the max is stored inverted, so one 0xFF fill clears both ends
    return uvec2(bin.x, ~bin.y);
}

// the first mask word of the tile under `pixel`
uint light_tile_base(uvec2 pixel, vec4 clusterHead)
{
    uint tilePx = uint(clusterHead.y + 0.5);
    uint tilesX = max(uint(clusterHead.z + 0.5), 1u);
    uvec2 tile = pixel / max(tilePx, 1u);
    tile.x = min(tile.x, tilesX - 1u);
    return (tile.y * tilesX + tile.x) * uint(clusterHead.w + 0.5);
}

uint light_tile_base(vec2 pixel, vec4 clusterHead)
{
    return light_tile_base(uvec2(pixel), clusterHead);
}

// the tile mask word `w` with the bits outside [lo, hi] cleared
uint light_word(uint base, uint w, uvec2 range)
{
    uint m = u_light_tiles[base + w];
    uint first = w * 32u;
    if (range.x > first) {
        m &= ~0u << (range.x - first);
    }
    if (range.y < first + 31u) {
        m &= ~0u >> (31u - (range.y - first));
    }
    return m;
}

uint light_slot(uint index)
{
    return u_light_keys[index] & LIGHT_SLOT_MASK;
}

#endif
