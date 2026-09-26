#version 450

// Mesh::quad squeezed into the highlighted rect, so only pixels near the glow run the fragment
layout(location = 0) in vec3 a_position;
layout(location = 1) in vec2 a_uv;

layout(location = 0) out vec2 v_uv;

#include "visu/outline_uniforms.glsl"

void main()
{
    vec2 t = a_position.xy * 0.5 + 0.5;
    vec2 ndc = mix(u_rect.xy, u_rect.zw, t);
    gl_Position = vec4(ndc, 0.0, 1.0);
    // textures are top-left, NDC is y up
    v_uv = vec2(ndc.x * 0.5 + 0.5, 0.5 - ndc.y * 0.5);
}
