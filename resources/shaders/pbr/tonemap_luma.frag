#version 450

// Log2 luminance of the HDR scene at an eighth of its size, before exposure: each texel is the
// mean radiance of its 8x8 block, read as 16 bilinear taps that each average a 2x2 quad.

layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 frag_luma;

#include "visu/tonemap_uniforms.glsl"

layout(set = 1, binding = 0) uniform sampler2D u_scene;

void main()
{
    vec2 scene = u_tm_size.zw;
    vec2 origin = floor(gl_FragCoord.xy) * 8.0;
    float sum = 0.0;
    for (int y = 0; y < 4; ++y) {
        for (int x = 0; x < 4; ++x) {
            vec2 at = clamp(origin + vec2(float(x) * 2.0 + 1.0, float(y) * 2.0 + 1.0), vec2(1.0), scene - vec2(1.0));
            sum += dot(max(texture(u_scene, at / scene).rgb, vec3(0.0)), TONEMAP_LUMA);
        }
    }
    frag_luma = vec4(log2(max(sum / 16.0, 1e-6)), 0.0, 0.0, 1.0);
}
