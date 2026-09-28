#version 450

layout(location = 0) in vec3 a_position;
layout(location = 1) in vec2 a_uv;

#include "visu/camera.glsl"

layout(std140, set = 0, binding = 0) uniform WaterUniforms {
    mat4 u_world;
    vec4 u_plane;
    vec4 u_absorption;
    vec4 u_ripple;
    vec4 u_flow;
    vec4 u_extra;
    // rgb scattering albedo of the body, w turbidity per metre
    vec4 u_body;
};

layout(location = 0) out vec3 v_world;
layout(location = 1) out vec3 v_local;
layout(location = 2) out vec2 v_uv;
layout(location = 3) out vec4 v_plane;
layout(location = 4) out vec4 v_absorption;
layout(location = 5) out vec4 v_ripple;
layout(location = 6) out vec4 v_flow;
layout(location = 7) out vec4 v_extra;
layout(location = 8) out vec4 v_body;

void main()
{
    vec4 world = u_world * vec4(a_position, 1.0);
    v_world = world.xyz;
    v_local = a_position;
    v_uv = a_uv;
    v_plane = u_plane;
    v_absorption = u_absorption;
    v_ripple = u_ripple;
    v_flow = u_flow;
    v_extra = u_extra;
    v_body = u_body;
    gl_Position = u_projection_view * world;
}
