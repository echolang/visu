#version 450

layout(location = 0) in vec3 v_position;
layout(location = 1) in vec3 v_normal;
layout(location = 2) in vec4 v_albedo_metallic;
layout(location = 3) in vec4 v_emissive_roughness;

#include "visu/gbuffer_layout.glsl"

void main()
{
    gbuffer_write(
        v_position,
        normalize(v_normal),
        v_albedo_metallic.rgb,
        v_albedo_metallic.a,
        v_emissive_roughness.a,
        v_emissive_roughness.rgb,
        1.0
    );
}
