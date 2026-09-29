/**
 * The aerial perspective table: the atmosphere of `sky.glsl` marched from the eye out to a
 * set of distances, over every view direction, for one eye height. A lit pixel reads the air
 * between it and the eye from here instead of marching, so distant ridges take the colour of
 * the sky behind them, per channel: blue at noon, warm at sunset, moonlit at night.
 *
 * The table is an array of two rgba16f layers:
 *   0 rgb the in-scattered light but for the sun's Mie lobe: sun Rayleigh and all of the moon,
 *     each under the texel's own phase, the lights, the multiple scattering stand-in and the
 *     exposure applied; a the path's Rayleigh optical depth
 *   1 rgb the sun's Mie light without its phase; a the path's Mie optical depth
 * The sun's Mie phase is applied per pixel, so the glow round a low sun keeps its sharpness;
 * everything else varies slowly across the sphere. The lookup interpolates the optical depths
 * and takes the transmittance per channel from them.
 *
 * Each layer is an atlas of AERIAL_SLICES distance slices side by side. A slice is
 * AERIAL_AZIMUTH texels of world azimuth with a gutter column either side (the neighbour
 * across the wrap), so bilinear filtering wraps without bleeding into the next slice. Rows are
 * the sine of the elevation over the whole sphere, squashed as sqrt towards the horizon
 * either side, where the path through the air changes fastest (no asin per pixel). Slice k holds the air out to
 * AERIAL_DISTANCE * ((k + 1) / AERIAL_SLICES)^2, so the near slices, where the eye sees
 * detail, are the densest. No uniforms here: the fill and every pass that fogs share it.
 * Mirrors visu::graphics::AERIAL_* (aerial.eco).
 */
#ifndef VISU_AERIAL_GLSL
#define VISU_AERIAL_GLSL

const float AERIAL_AZIMUTH = 64.0;
const float AERIAL_SLICE_WIDTH = 66.0;
const float AERIAL_ELEVATION = 32.0;
const float AERIAL_SLICES = 32.0;
const float AERIAL_WIDTH = 2112.0;
const float AERIAL_DISTANCE = 64000.0;
const float AERIAL_PI = 3.14159265359;

/**
 * The world direction a table row `v` (0 straight down, 1 straight up) and azimuth texel `i`
 * (0 to AERIAL_AZIMUTH - 1) stand for.
 */
vec3 aerial_dir(float v, float i)
{
    float c = 2.0 * v - 1.0;
    float y = sign(c) * c * c;
    float azimuth = ((i + 0.5) / AERIAL_AZIMUTH - 0.5) * 2.0 * AERIAL_PI;
    float ce = sqrt(max(1.0 - y * y, 0.0));
    return vec3(ce * cos(azimuth), y, ce * sin(azimuth));
}

/**
 * The distance slice `k` holds the air out to, in metres.
 */
float aerial_slice_distance(float k)
{
    float x = (k + 1.0) / AERIAL_SLICES;
    return AERIAL_DISTANCE * x * x;
}

/**
 * Where `dir` reads a slice: x the azimuth in texels from the slice's first real column
 * (0 to AERIAL_AZIMUTH), y the normalised row, clamped to the row centres.
 */
vec2 aerial_uv(vec3 dir)
{
    float y = clamp(dir.y, -1.0, 1.0);
    float v = 0.5 + 0.5 * sign(y) * sqrt(abs(y));
    float half_texel = 0.5 / AERIAL_ELEVATION;
    float u = (atan(dir.z, dir.x) / (2.0 * AERIAL_PI) + 0.5) * AERIAL_AZIMUTH;
    return vec2(u, clamp(v, half_texel, 1.0 - half_texel));
}

/**
 * The continuous slice coordinate of a point `d` metres away: slice k sits at k, the eye at
 * -1 (no air at all).
 */
float aerial_slice(float d)
{
    return sqrt(max(d, 0.0) / AERIAL_DISTANCE) * AERIAL_SLICES - 1.0;
}

/**
 * The atlas coordinate of `uv` (from `aerial_uv`) in slice `k`.
 */
vec2 aerial_atlas(vec2 uv, float k)
{
    return vec2((k * AERIAL_SLICE_WIDTH + 1.0 + uv.x) / AERIAL_WIDTH, uv.y);
}

#endif
