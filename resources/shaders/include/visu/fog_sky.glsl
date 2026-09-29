/**
 * The fog's sky table: the atmosphere's radiance over the upper hemisphere, phase and lights
 * applied and the sky exposure folded in, one rgba16f texel per direction. `HeightFog.fromSky`
 * fogs every pixel toward it, so the haze takes the colour of the sky behind it.
 *
 * u is the world azimuth (wrapped), v the elevation from the horizon (0) to the zenith (1),
 * squashed as sqrt so the horizon, where the fog looks, gets most of the rows. No sky uniforms
 * here: the water pass reads it without the sky block. Mirrors visu::graphics::FOG_SKY_WIDTH /
 * FOG_SKY_HEIGHT and `fogSkyUv` / `fogSkyDir` (fogsky.eco).
 */
#ifndef VISU_FOG_SKY_GLSL
#define VISU_FOG_SKY_GLSL

const float FOG_SKY_WIDTH = 64.0;
const float FOG_SKY_HEIGHT = 32.0;
const float FOG_SKY_PI = 3.14159265358979;

/**
 * The table coordinate of the upper-hemisphere direction `dir`, v clamped to the rows'
 * centres.
 */
vec2 fog_sky_uv(vec3 dir)
{
    float elevation = asin(clamp(dir.y, 0.0, 1.0));
    float v = sqrt(elevation / (0.5 * FOG_SKY_PI));
    float half_texel = 0.5 / FOG_SKY_HEIGHT;
    float u = atan(dir.z, dir.x) / (2.0 * FOG_SKY_PI) + 0.5;
    return vec2(u, clamp(v, half_texel, 1.0 - half_texel));
}

/**
 * The direction a table texel at `uv` stands for.
 */
vec3 fog_sky_dir(vec2 uv)
{
    float elevation = uv.y * uv.y * 0.5 * FOG_SKY_PI;
    float azimuth = (uv.x - 0.5) * 2.0 * FOG_SKY_PI;
    float c = cos(elevation);
    return vec3(c * cos(azimuth), sin(elevation), c * sin(azimuth));
}

/**
 * The horizon in `dir`'s azimuth, lifted to at least y = 0.02 so the sample is sky. Straight up
 * or down has no azimuth: `fallback` (towards the sun), then +X.
 */
vec3 fog_sky_horizon(vec3 dir, vec3 fallback)
{
    vec2 xz = dir.xz;
    float horiz = length(xz);

    if (horiz < 1e-4) {
        xz = fallback.xz;
        horiz = length(xz);

        if (horiz < 1e-4) {
            xz = vec2(1.0, 0.0);
            horiz = 1.0;
        }
    }

    xz /= horiz;
    return normalize(vec3(xz.x, max(dir.y, 0.02), xz.y));
}

#endif
