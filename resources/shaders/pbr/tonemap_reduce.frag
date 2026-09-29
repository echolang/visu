#version 450

// 64 x 32 coarse cells down to 8 x 4: r the mean log2 luminance, g the brightest cell. The
// exposure pass reads these 32 texels instead of all 2048.

layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 frag_stats;

layout(set = 1, binding = 0) uniform sampler2D u_coarse;

void main()
{
    ivec2 origin = ivec2(gl_FragCoord.xy) * 8;
    float sum = 0.0;
    float peak = -64.0;
    for (int y = 0; y < 8; ++y) {
        for (int x = 0; x < 8; ++x) {
            vec2 v = texelFetch(u_coarse, origin + ivec2(x, y), 0).rg;
            sum += v.r;
            peak = max(peak, v.g);
        }
    }
    frag_stats = vec4(sum / 64.0, peak, 0.0, 1.0);
}
