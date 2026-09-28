#version 450

#pragma visu variant lut SKY_VIEW_LUT=1

layout(location = 0) in vec3 v_direction;
layout(location = 0) out vec4 frag_color;

#include "visu/camera.glsl"
#define VISU_FOG_RAYS
#include "visu/fog.glsl"
#include "visu/functions/tone_mapping.glsl"
#include "visu/functions/gamma_corr.glsl"

#ifdef SKY_VIEW_LUT
#include "visu/sky_view.glsl"
layout(set = 1, binding = 1) uniform sampler2DArray u_sky_view;
#endif

void main()
{
    vec3 dir = normalize(v_direction);
#ifdef SKY_VIEW_LUT
    vec3 color = min(sky_radiance_lut(dir, u_sky_view), vec3(65504.0));
#else
    vec3 color = min(sky_radiance(dir), vec3(65504.0));
#endif
    color = fog_apply_sky_rays(color, dir, gl_FragCoord.xy * u_resolution.zw);
    color = apply_tonemap(color);
    color = gamma_correct(color);
    frag_color = vec4(color, 1.0);
}
