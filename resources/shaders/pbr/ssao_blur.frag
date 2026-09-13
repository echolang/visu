#version 450

layout(location = 0) in vec2 v_uv;
layout(location = 0) out float frag_ao;

layout(set = 1, binding = 0) uniform sampler2D ssao_noisy;

void main()
{
    vec2 texel = 1.0 / vec2(textureSize(ssao_noisy, 0));
    float total = 0.0;

    // the noise repeats every four texels, so a four-wide box clears it
    for (int x = -2; x <= 1; ++x)
    {
        for (int y = -2; y <= 1; ++y)
        {
            total += texture(ssao_noisy, v_uv + vec2(float(x), float(y)) * texel).r;
        }
    }

    frag_ao = total / 16.0;
}
