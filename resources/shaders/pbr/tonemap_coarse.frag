#version 450

// The luma image folded into 64 x 32: r the mean log2 luminance of the texels a cell covers
// (the input of the wide Gaussian base), g the brightest of them (the exposure's highlight
// meter).

layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 frag_coarse;

#include "visu/tonemap_uniforms.glsl"

layout(set = 1, binding = 0) uniform sampler2D u_luma;

void main()
{
    ivec2 cell = ivec2(gl_FragCoord.xy);
    ivec2 luma = tonemap_luma_size();
    ivec2 lo;
    ivec2 hi;
    tonemap_cell_span(cell, luma, lo, hi);
    float sum = 0.0;
    float peak = -64.0;
    float n = 0.0;
    for (int y = lo.y; y < hi.y; ++y) {
        for (int x = lo.x; x < hi.x; ++x) {
            float v = texelFetch(u_luma, clamp(ivec2(x, y), ivec2(0), luma - ivec2(1)), 0).r;
            sum += v;
            peak = max(peak, v);
            n += 1.0;
        }
    }
    frag_coarse = vec4(sum / max(n, 1.0), peak, 0.0, 1.0);
}
