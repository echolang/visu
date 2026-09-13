#version 450

layout(location = 0) in vec3 v_position;
layout(location = 0) out vec4 frag_color;

layout(set = 1, binding = 0) uniform sampler2D u_equirect;

// 1/(2 pi), 1/pi
const vec2 INV_ATAN = vec2(0.15915494, 0.31830989);

vec2 sample_sphere(vec3 v)
{
    // v counts down from +Y because the decoder hands us row 0 = image top
    return vec2(atan(v.z, v.x) * INV_ATAN.x + 0.5, 0.5 - asin(v.y) * INV_ATAN.y);
}

void main()
{
    // textureLod, not texture: inside a cube face the screen-space
    // derivatives of an equirectangular lookup are meaningless (they
    // blow up at the seam), and the source has no mips anyway
    vec3 color = textureLod(u_equirect, sample_sphere(normalize(v_position)), 0.0).rgb;
    // the cube is rgba16f, so keep the range it can hold
    frag_color = vec4(min(color, vec3(65504.0)), 1.0);
}
