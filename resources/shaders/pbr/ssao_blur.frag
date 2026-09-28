#version 450

// the 7-wide box is separable: a horizontal pass into an r32f intermediate, then this vertical
// pass, 14 taps a pixel instead of 49 for the same average
#pragma visu variant vertical SSAO_BLUR_VERTICAL=1

layout(location = 0) in vec2 v_uv;
layout(location = 0) out float frag_ao;

layout(set = 1, binding = 0) uniform sampler2D ssao_noisy;

void main()
{
    vec2 texel = 1.0 / vec2(textureSize(ssao_noisy, 0));
#ifdef SSAO_BLUR_VERTICAL
    vec2 step = vec2(0.0, texel.y);
#else
    vec2 step = vec2(texel.x, 0.0);
#endif
    float total = 0.0;

    // 7-wide box; the 4x4 noise tile is gone and leftover kernel
    // variance on curved surfaces is softened
    for (int i = -3; i <= 3; ++i)
    {
        total += texture(ssao_noisy, v_uv + float(i) * step).r;
    }

    frag_ao = total / 7.0;
}
