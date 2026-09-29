#version 450

// Fills the aerial perspective table: per texel, the atmosphere march from the eye along the
// texel's direction, stopped at its slice's distance, split into the two layers
// `visu/aerial.glsl` describes. Drawn into both layers of the table at once.

layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 aerial_light;
layout(location = 1) out vec4 aerial_sun_m;

#include "visu/sky.glsl"
#include "visu/aerial.glsl"

const float AERIAL_HALF_MAX = 65504.0;

void main()
{
    float column = floor(gl_FragCoord.x);
    float k = floor(column / AERIAL_SLICE_WIDTH);
    float local = column - k * AERIAL_SLICE_WIDTH;
    // the gutters repeat the neighbour across the wrap: column 0 is the last azimuth, the
    // last column the first
    float i = mod(local - 1.0 + AERIAL_AZIMUTH, AERIAL_AZIMUTH);
    vec3 dir = aerial_dir(gl_FragCoord.y / AERIAL_ELEVATION, i);
    SkyScatter s = sky_scatter_to(dir, aerial_slice_distance(k), int(u_sky_params.x), int(u_sky_params.y));
    // everything but the sun's Mie lobe under this texel's phase, lights and exposure applied
    float scale = SKY_MULTIPLE_SCATTERING * u_sky_ground.w;
    float mu = dot(dir, u_sky_sun.xyz);
    vec3 light = (u_sky_sun.w * scale) * s.sun_r * sky_phase_rayleigh(mu);

    if (u_sky_moon.w > 0.0) {
        float mu_m = dot(dir, u_sky_moon.xyz);
        light += (u_sky_moon.w * scale) * u_sky_moon_color.rgb
            * (s.moon_r * sky_phase_rayleigh(mu_m) + s.moon_m * sky_phase_mie(mu_m));
    }

    // the path's optical depth in metres of ground-level air, Rayleigh and Mie apart: the lookup
    // interpolates these and takes the transmittance per channel from them. Ozone sits 25 km up,
    // out of reach of any path to the ground, so it is left out
    float rayleigh_depth = s.depth.x;
    float mie_depth = s.depth.y;

    aerial_light = vec4(min(light, vec3(AERIAL_HALF_MAX)), min(rayleigh_depth, AERIAL_HALF_MAX));
    aerial_sun_m = vec4(min((u_sky_sun.w * scale) * s.sun_m, vec3(AERIAL_HALF_MAX)), min(mie_depth, AERIAL_HALF_MAX));
}
