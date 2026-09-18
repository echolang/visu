#version 450

layout(location = 0) in vec3 aPos;
layout(location = 0) out vec3 vPos;
layout(location = 1) out vec4 vColor;

layout(std140, set = 0, binding = 0) uniform CubeDrawData {
    mat4 u_model;
    vec4 u_color;
};

#include "visu/camera.glsl"

void main()
{
    vec4 world = u_model * vec4(aPos, 1.0);
    vPos = world.xyz;
    vColor = u_color;
    gl_Position = u_projection_view * world;
}
