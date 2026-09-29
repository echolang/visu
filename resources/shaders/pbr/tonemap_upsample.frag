#version 450

// The blurred 64 x 32 base to 256 x 128 through a cubic B-spline (four bilinear taps), so the
// resolve's bilinear read of it shows no cell grid.

layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 frag_base;

layout(set = 1, binding = 0) uniform sampler2D u_base;

void main()
{
    vec2 size = vec2(64.0, 32.0);
    vec2 st = gl_FragCoord.xy / vec2(256.0, 128.0) * size - 0.5;
    vec2 i = floor(st);
    vec2 f = st - i;
    vec2 f2 = f * f;
    vec2 f3 = f2 * f;
    vec2 w0 = (1.0 - 3.0 * f + 3.0 * f2 - f3) / 6.0;
    vec2 w1 = (4.0 - 6.0 * f2 + 3.0 * f3) / 6.0;
    vec2 w2 = (1.0 + 3.0 * f + 3.0 * f2 - 3.0 * f3) / 6.0;
    vec2 w3 = f3 / 6.0;
    vec2 s0 = w0 + w1;
    vec2 s1 = w2 + w3;
    // each pair of texels as one bilinear tap placed by their weights
    vec2 p0 = (i - 0.5 + w1 / s0) / size;
    vec2 p1 = (i + 1.5 + w3 / s1) / size;
    float v = s0.y * (s0.x * texture(u_base, vec2(p0.x, p0.y)).r + s1.x * texture(u_base, vec2(p1.x, p0.y)).r)
        + s1.y * (s0.x * texture(u_base, vec2(p0.x, p1.y)).r + s1.x * texture(u_base, vec2(p1.x, p1.y)).r);
    frag_base = vec4(v, 0.0, 0.0, 1.0);
}
