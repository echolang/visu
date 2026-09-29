#version 450

layout(location = 0) in vec3 v_direction;
layout(location = 0) out vec4 frag_color;

#include "visu/camera.glsl"
#define VISU_FOG_SKY_SLOT 2
#define VISU_FOG_SKY_ONLY
#define VISU_FOG_RAYS
#include "visu/fog.glsl"

#include "visu/sky_view.glsl"
layout(set = 1, binding = 1) uniform sampler2DArray u_sky_view;

void main()
{
    vec3 dir = normalize(v_direction);
    vec3 color = min(sky_radiance_lut(dir, u_sky_view), vec3(65504.0));
    color = fog_apply_sky_rays(color, dir, gl_FragCoord.xy * u_resolution.zw);
    frag_color = vec4(color, 1.0);
}
