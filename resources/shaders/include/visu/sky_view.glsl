/**
 * Sky-view LUT: the atmosphere march of `sky.glsl` tabulated over view directions for one
 * observer height, so a sky pixel reads five texels instead of marching 16 x 8 samples.
 *
 * The table is an array of five rgba16f layers, one texel per direction:
 *   0 rgb sun Rayleigh, a transmittance.r
 *   1 rgb sun Mie,      a transmittance.g
 *   2 rgb moon Rayleigh, a transmittance.b
 *   3 rgb moon Mie
 *   4 rgb ground radiance times transmittance (ground rows only)
 * The phase functions are left out of the table and applied per pixel, so the Mie glow
 * around the sun keeps its full sharpness; what the table holds varies slowly across the
 * dome. The disc, the moon and the stars stay analytic per pixel.
 *
 * u is the world azimuth (wrapped). v splits at the horizon: the top half is sky, the bottom
 * half ground, each squashed towards the horizon (Hillaire 2020) where the atmosphere changes
 * fastest. A lookup never blends across the horizon: v is clamped to its own half.
 * Mirrors visu::graphics::SKY_VIEW_WIDTH / SKY_VIEW_HEIGHT (skyview.eco).
 */
#ifndef VISU_SKY_VIEW_GLSL
#define VISU_SKY_VIEW_GLSL

#include "visu/sky.glsl"

const float SKY_VIEW_WIDTH = 256.0;
const float SKY_VIEW_HEIGHT = 128.0;
const int SKY_VIEW_LAYERS = 5;

/**
 * Zenith angle of the geometric horizon from the observer, and the angle the ground spans
 * below it (x horizon zenith, y ground span).
 */
vec2 sky_view_horizon()
{
    float h = max(u_sky_origin.y, 1.0);
    float r = u_sky_params.z + h;
    // r^2 - R^2 without subtracting two numbers near 4e13
    float cos_beta = sqrt(h * (2.0 * u_sky_params.z + h)) / r;
    float beta = acos(clamp(cos_beta, 0.0, 1.0));
    return vec2(SKY_PI - beta, beta);
}

/**
 * The view direction a LUT texel at `uv` stands for.
 */
vec3 sky_view_dir(vec2 uv)
{
    vec2 horizon = sky_view_horizon();
    float zenith;

    if (uv.y < 0.5) {
        float c = 1.0 - 2.0 * uv.y;
        zenith = horizon.x * (1.0 - c * c);
    } else {
        float c = 2.0 * uv.y - 1.0;
        zenith = horizon.x + horizon.y * c * c;
    }

    float azimuth = (uv.x - 0.5) * 2.0 * SKY_PI;
    float s = sin(zenith);
    return vec3(s * cos(azimuth), cos(zenith), s * sin(azimuth));
}

/**
 * Where `dir` reads the LUT. `ground` is whether the ray hits the planet, decided by the
 * caller with the same test the march uses, so a pixel never takes the other half's value.
 */
vec2 sky_view_uv(vec3 dir, bool ground)
{
    vec2 horizon = sky_view_horizon();
    float zenith = acos(clamp(dir.y, -1.0, 1.0));
    float half_texel = 0.5 / SKY_VIEW_HEIGHT;
    float v;

    if (!ground) {
        float c = sqrt(max(1.0 - zenith / horizon.x, 0.0));
        v = clamp(0.5 * (1.0 - c), half_texel, 0.5 - half_texel);
    } else {
        float c = sqrt(max((zenith - horizon.x) / horizon.y, 0.0));
        v = clamp(0.5 + 0.5 * c, 0.5 + half_texel, 1.0 - half_texel);
    }

    float u = atan(dir.z, dir.x) / (2.0 * SKY_PI) + 0.5;
    return vec2(u, v);
}

/**
 * `sky_radiance` from the LUT: the table's march under this pixel's phase, the ground
 * below the horizon, the disc, the moon and the stars above it. Exposure applied.
 */
vec3 sky_radiance_lut(vec3 dir, sampler2DArray lut)
{
    bool ground = sky_ray_sphere(sky_observer(), dir, u_sky_params.z).x > 0.0;
    vec2 uv = sky_view_uv(dir, ground);
    vec4 sun_r = textureLod(lut, vec3(uv, 0.0), 0.0);
    vec4 sun_m = textureLod(lut, vec3(uv, 1.0), 0.0);
    // layer 2 carries the blue transmittance, so it is always read; the moon Mie layer only
    // holds light while the moon is up and lit, which is the same for every pixel
    vec4 moon_r = textureLod(lut, vec3(uv, 2.0), 0.0);
    vec4 moon_m = vec4(0.0);

    if (u_sky_moon.w > 0.0) {
        moon_m = textureLod(lut, vec3(uv, 3.0), 0.0);
    }

    vec3 transmittance = vec3(sun_r.a, sun_m.a, moon_r.a);
    vec3 color = sky_scatter_color(dir, sun_r.rgb, sun_m.rgb, moon_r.rgb, moon_m.rgb);

    if (!ground) {
        return sky_lights(dir, transmittance, color) * u_sky_ground.w;
    }

    vec3 lit_ground = textureLod(lut, vec3(uv, 4.0), 0.0).rgb;
    return (color + lit_ground) * u_sky_ground.w;
}

#endif
