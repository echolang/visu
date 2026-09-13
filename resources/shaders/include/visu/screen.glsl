/**
 * Screen-space conventions in one place. Texture origin is top-left
 * on both backends and NDC +Y is up, so the two differ by a Y flip.
 */
#ifndef VISU_SCREEN_GLSL
#define VISU_SCREEN_GLSL

vec2 ndc_from_uv(vec2 uv)
{
    return vec2(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0);
}

vec2 uv_from_ndc(vec2 ndc)
{
    return vec2(ndc.x * 0.5 + 0.5, 0.5 - ndc.y * 0.5);
}

#endif
