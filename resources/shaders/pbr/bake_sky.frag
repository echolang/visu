#version 450

layout(location = 0) in vec3 v_position;
layout(location = 0) out vec4 frag_color;

#include "visu/sky.glsl"

void main()
{
    // linear radiance into an rgba16f face; the disk flag is off for a probe
    frag_color = vec4(min(sky_radiance(normalize(v_position)), vec3(65504.0)), 1.0);
}
