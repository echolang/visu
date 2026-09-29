#version 450

// Fills the fog's sky table (`visu/fog_sky.glsl`): one atmosphere march per texel at the
// texel's direction, phase and lights applied, times the sky exposure. Drawn only when the
// sky moved.

layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 fog_sky;

#include "visu/sky.glsl"
#include "visu/fog_sky.glsl"

void main()
{
    vec2 uv = gl_FragCoord.xy / vec2(FOG_SKY_WIDTH, FOG_SKY_HEIGHT);
    vec3 dir = fog_sky_dir(uv);
    vec3 transmittance;
    float t_ground;
    vec3 radiance = sky_inscatter_n(dir, int(u_sky_params.x), int(u_sky_params.y), transmittance, t_ground);
    fog_sky = vec4(min(radiance * u_sky_ground.w, vec3(65504.0)), 1.0);
}
