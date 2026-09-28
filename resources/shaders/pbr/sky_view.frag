#version 450

// Fills the sky-view LUT: one full atmosphere march per texel, at the texel's view
// direction, split into the layers `visu/sky_view.glsl` describes. Drawn into the five
// slices of the table at once.

layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 lut_sun_r;
layout(location = 1) out vec4 lut_sun_m;
layout(location = 2) out vec4 lut_moon_r;
layout(location = 3) out vec4 lut_moon_m;
layout(location = 4) out vec4 lut_ground;

#include "visu/sky_view.glsl"

const float LUT_HALF_MAX = 65504.0;

void main()
{
    vec2 uv = gl_FragCoord.xy / vec2(SKY_VIEW_WIDTH, SKY_VIEW_HEIGHT);
    vec3 dir = sky_view_dir(uv);
    SkyScatter s = sky_scatter_n(dir, int(u_sky_params.x), int(u_sky_params.y));
    vec3 ground = vec3(0.0);

    if (s.t_ground > 0.0) {
        ground = s.transmittance * sky_ground(dir, s.t_ground);
    }

    lut_sun_r = vec4(min(s.sun_r, vec3(LUT_HALF_MAX)), s.transmittance.r);
    lut_sun_m = vec4(min(s.sun_m, vec3(LUT_HALF_MAX)), s.transmittance.g);
    lut_moon_r = vec4(min(s.moon_r, vec3(LUT_HALF_MAX)), s.transmittance.b);
    lut_moon_m = vec4(min(s.moon_m, vec3(LUT_HALF_MAX)), 1.0);
    lut_ground = vec4(min(ground, vec3(LUT_HALF_MAX)), 1.0);
}
