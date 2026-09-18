#version 450

layout(location = 0) in vec3 v_position;
layout(location = 1) in vec4 v_color;

#include "visu/gbuffer_layout.glsl"

void main()
{
    // no albedo and no metal: the line comes back out of the light pass as its own colour,
    // whatever the sun and the probes are doing to the geometry around it
    gbuffer_write(v_position, vec3(0.0, 1.0, 0.0), vec3(0.0), 0.0, 1.0, v_color.rgb, 1.0);
}
