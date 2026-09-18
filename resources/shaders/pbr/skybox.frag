#version 450

layout(location = 0) in vec3 v_direction;
layout(location = 0) out vec4 frag_color;

layout(set = 1, binding = 0) uniform samplerCube u_skybox;

#include "visu/fog.glsl"
#include "visu/functions/tone_mapping.glsl"
#include "visu/functions/gamma_corr.glsl"

void main()
{
    vec3 dir = normalize(v_direction);
    vec3 color = texture(u_skybox, dir).rgb;
    color = fog_apply_sky(color, dir);
    color = apply_tonemap(color);
    color = gamma_correct(color);
    frag_color = vec4(color, 1.0);
}
