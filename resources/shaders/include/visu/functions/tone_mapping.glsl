#ifndef TONE_MAPPING_GLSL
#define TONE_MAPPING_GLSL
/**
 * Common tone mapping functions
 * ----------------------------------------------------------------------------
 */

// the curve is a compile-time pick: each `tonemap.frag` variant defines TONEMAP_METHOD, and
// `ToneCurve.program` in src/graphics/deferred/tonemap.eco names the variant per curve
//   TONEMAP_NEUTRAL  (1) - Khronos PBR neutral tone mapper
//   TONEMAP_ACES     (2) - ACES, Stephen Hill's fit of the RRT and the sRGB ODT (default)
//   TONEMAP_REINHARD (3) - extended Reinhard with a white point
//   TONEMAP_FILMIC   (4) - visu's filmic curve in the tone-map gamut (tonemap.frag, it reads
//                          the tone-map uniforms)
#define TONEMAP_NONE 0
#define TONEMAP_NEUTRAL 1
#define TONEMAP_ACES 2
#define TONEMAP_REINHARD 3
#define TONEMAP_FILMIC 4

#ifndef TONEMAP_METHOD
#define TONEMAP_METHOD TONEMAP_ACES
#endif

// exposed radiance the Reinhard curve maps to display white (TONE_REINHARD_WHITE)
const float TONEMAP_REINHARD_WHITE = 4.0;

/**
 * ACES fitted, after Stephen Hill (BakingLab, MIT): Rec.709 into AP1 with the RRT's saturation
 * folded in, the rational fit of RRT + ODT per channel, then the ODT's matrix back to Rec.709.
 * The rows mirror `acesInput` / `acesOutput` in src/graphics/deferred/tonemap.eco.
 */
vec3 tonemap_aces_fit(vec3 v)
{
    vec3 a = v * (v + 0.0245786) - 0.000090537;
    vec3 b = v * (0.983729 * v + 0.4329510) + 0.238081;
    return a / b;
}

vec3 tonemap_aces(vec3 color)
{
    vec3 v = vec3(
        dot(vec3(0.59719, 0.35458, 0.04823), color),
        dot(vec3(0.07600, 0.90834, 0.01566), color),
        dot(vec3(0.02840, 0.13383, 0.83777), color)
    );
    v = tonemap_aces_fit(v);
    vec3 o = vec3(
        dot(vec3(1.60475, -0.53108, -0.07367), v),
        dot(vec3(-0.10208, 1.10813, -0.00605), v),
        dot(vec3(-0.00327, -0.07276, 1.07602), v)
    );
    return clamp(o, 0.0, 1.0);
}

/**
 * Extended Reinhard: `TONEMAP_REINHARD_WHITE` maps to 1.
 */
vec3 tonemap_reinhard(vec3 x)
{
    const float w2 = TONEMAP_REINHARD_WHITE * TONEMAP_REINHARD_WHITE;
    return (x * (1.0 + x / w2)) / (1.0 + x);
}

/**
 * Khronos PBR Neutral Tone Mapper
 * https://github.com/KhronosGroup/ToneMapping/tree/main/PBR_Neutral
 */
vec3 tonemap_neutral(vec3 color)
{
    const float startCompression = 0.8 - 0.04;
    const float desaturation = 0.15;

    float x = min(color.r, min(color.g, color.b));
    float offset = x < 0.08 ? x - 6.25 * x * x : 0.04;
    color -= offset;

    float peak = max(color.r, max(color.g, color.b));
    if (peak < startCompression) return color;

    const float d = 1.0 - startCompression;
    float newPeak = 1.0 - d * d / (peak + d - startCompression);
    color *= newPeak / peak;

    float g = 1.0 - 1.0 / (desaturation * (peak - newPeak) + 1.0);
    return mix(color, vec3(newPeak), g);
}

/**
 * Applies the curve TONEMAP_METHOD picks, for the curves that need no uniforms. The filmic
 * curve lives in tonemap.frag, which holds its constants.
 */
vec3 apply_tonemap(vec3 color)
{
#if TONEMAP_METHOD == TONEMAP_NEUTRAL
    return tonemap_neutral(color);
#elif TONEMAP_METHOD == TONEMAP_ACES
    return tonemap_aces(color);
#elif TONEMAP_METHOD == TONEMAP_REINHARD
    return tonemap_reinhard(color);
#else
    return color;
#endif
}

#endif
