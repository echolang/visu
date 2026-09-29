#version 450

layout(location = 0) in vec3 v_direction;
layout(location = 0) out vec4 frag_color;

layout(set = 1, binding = 0) uniform samplerCube u_skybox;

#include "visu/camera.glsl"
#define VISU_FOG_SKY_SLOT 1
#define VISU_FOG_SKY_ONLY
#define VISU_FOG_RAYS
#include "visu/fog.glsl"

void main()
{
    vec3 dir = normalize(v_direction);
    vec3 color = texture(u_skybox, dir).rgb;
    color = fog_apply_sky_rays(color, dir, gl_FragCoord.xy * u_resolution.zw);
    frag_color = vec4(color, 1.0);
}
