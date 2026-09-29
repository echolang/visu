#version 450

#pragma visu variant local TONEMAP_LOCAL=1
#pragma visu variant neutral TONEMAP_METHOD=1
#pragma visu variant neutral_local TONEMAP_METHOD=1 TONEMAP_LOCAL=1
#pragma visu variant reinhard TONEMAP_METHOD=3
#pragma visu variant reinhard_local TONEMAP_METHOD=3 TONEMAP_LOCAL=1
#pragma visu variant filmic TONEMAP_METHOD=4
#pragma visu variant filmic_local TONEMAP_METHOD=4 TONEMAP_LOCAL=1

// The display end of the deferred frame: reads the lit HDR scene (light, sky and water, all
// linear radiance) and writes the display-encoded colour the outline, the UI and the present
// blit draw over. The one place exposure, the curve and the gamma run.
//
// With `local` the luminance is first compressed against an edge-aware base in log2:
//   Io = c (B - M) + d (Ii - B) + M
// where B mixes the bilateral grid and a wide Gaussian, M is the midpoint, c the contrast of
// the base (above or below M) and d the detail kept. Colour scales by the luminance change, so
// chromaticity is kept. The curve is this variant's TONEMAP_METHOD (`ToneCurve.program` picks
// the variant): ACES (the default, after its pre-exposure in u_tm_exposure.w), Khronos PBR
// Neutral, Reinhard, or the filmic curve, which runs per channel in a wide gamut with white
// balance folded into the matrix that enters it.

layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 fragment_color;

#include "visu/functions/tone_mapping.glsl"
#include "visu/functions/gamma_corr.glsl"
#include "visu/tonemap_uniforms.glsl"

layout(set = 1, binding = 0) uniform sampler2D u_scene;
layout(set = 1, binding = 1) uniform sampler2D u_exposure;
#ifdef TONEMAP_LOCAL
layout(set = 1, binding = 2) uniform sampler2D u_grid;
layout(set = 1, binding = 3) uniform sampler2D u_base;

// the edge-aware base at this pixel: the grid cell by position, the slice by the pixel's own
// log luminance, normalised by the weight that landed there
float grid_base(vec2 uv, float level)
{
    float last = u_tm_grid.w - 1.0;
    float z = clamp((level - u_tm_grid.y) / u_tm_grid.z * last, 0.0, last);
    float z0 = floor(z);
    float z1 = min(z0 + 1.0, last);
    vec2 cell = clamp(uv * vec2(64.0, 32.0), vec2(0.5), vec2(63.5, 31.5));
    float width = 64.0 * u_tm_grid.w;
    vec2 a = texture(u_grid, vec2((z0 * 64.0 + cell.x) / width, cell.y / 32.0)).rg;
    vec2 b = texture(u_grid, vec2((z1 * 64.0 + cell.x) / width, cell.y / 32.0)).rg;
    vec2 s = mix(a, b, z - z0);
    if (s.y < 1e-4) {
        return level;
    }
    return s.x / s.y;
}
#endif

vec3 tm_row(vec4 r0, vec4 r1, vec4 r2, vec3 c)
{
    return vec3(dot(r0.xyz, c), dot(r1.xyz, c), dot(r2.xyz, c));
}

// x^a / ((x^a)^d b + c): contrast a, shoulder d, b and c solved so the midpoint and the white
// point land where the settings put them
vec3 tm_filmic(vec3 x)
{
    vec3 z = pow(max(x, vec3(0.0)), vec3(u_tm_curve.x));
    return z / (pow(z, vec3(u_tm_curve.y)) * u_tm_curve.z + u_tm_curve.w);
}

void main()
{
    vec4 hdr = texelFetch(u_scene, ivec2(gl_FragCoord.xy), 0);
    float ev = tonemap_ev(u_exposure);
    vec3 color = hdr.rgb * exp2(ev);

#ifdef TONEMAP_LOCAL
    float level = log2(max(dot(max(color, vec3(0.0)), TONEMAP_LUMA), 1e-6));
    vec2 uv = gl_FragCoord.xy / u_tm_size.zw;
    float gaussian = texture(u_base, uv).r + ev;
    float base = mix(gaussian, grid_base(uv, level), u_tm_grid.x);
    float mid = u_tm_local.x;
    float contrast = base > mid ? u_tm_local.y : u_tm_local.z;
    float target = contrast * (base - mid) + u_tm_local.w * (level - base) + mid;
    color *= exp2(target - level);
#endif

    color *= u_tm_exposure.w;
#if TONEMAP_METHOD == TONEMAP_FILMIC
    color = tm_row(u_tm_in[0], u_tm_in[1], u_tm_in[2], color);
    color = tm_filmic(color);
    color = clamp(tm_row(u_tm_out[0], u_tm_out[1], u_tm_out[2], color), 0.0, 1.0);
#else
    color = apply_tonemap(color);
#endif
    fragment_color = vec4(gamma_correct(color), hdr.a);
}
