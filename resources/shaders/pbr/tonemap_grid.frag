#version 450

// Builds the bilateral grid: 64 x 32 cells by 64 log-luminance slices, laid side by side in a
// 4096 x 32 atlas (slice s is columns 64 s to 64 s + 63). A fragment is one cell of one slice:
// it gathers the luma texels its cell covers, exposed, and each adds (w V, w) with a tent
// weight into the two slices nearest its value. Sums are divided by the texel count, so the
// weights stay in 0..1 whatever the resolution. A gather, not a splat: no atomics, the same
// sums in the same order every frame.

layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 frag_grid;

#include "visu/tonemap_uniforms.glsl"

layout(set = 1, binding = 0) uniform sampler2D u_luma;
layout(set = 1, binding = 1) uniform sampler2D u_exposure;

void main()
{
    ivec2 p = ivec2(gl_FragCoord.xy);
    float slice = float(p.x / 64);
    ivec2 cell = ivec2(p.x % 64, p.y);
    ivec2 luma = tonemap_luma_size();
    ivec2 lo;
    ivec2 hi;
    tonemap_cell_span(cell, luma, lo, hi);
    float ev = tonemap_ev(u_exposure);
    float last = u_tm_grid.w - 1.0;
    vec2 sum = vec2(0.0);
    float n = 0.0;
    for (int y = lo.y; y < hi.y; ++y) {
        for (int x = lo.x; x < hi.x; ++x) {
            float v = texelFetch(u_luma, clamp(ivec2(x, y), ivec2(0), luma - ivec2(1)), 0).r + ev;
            float z = clamp((v - u_tm_grid.y) / u_tm_grid.z * last, 0.0, last);
            float w = max(1.0 - abs(z - slice), 0.0);
            sum += vec2(w * v, w);
            n += 1.0;
        }
    }
    frag_grid = vec4(sum / max(n, 1.0), 0.0, 1.0);
}
