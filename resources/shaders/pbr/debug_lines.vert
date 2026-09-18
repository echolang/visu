#version 450

layout(location = 0) in vec3 a_position;
layout(location = 1) in vec4 a_color;

layout(location = 0) out vec3 v_position;
layout(location = 1) out vec4 v_color;

#include "visu/camera.glsl"

void main()
{
    v_position = a_position;
    v_color = a_color;

    gl_Position = u_projection_view * vec4(a_position, 1.0);
}
