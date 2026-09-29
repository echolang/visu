#ifndef VISU_TONEMAP_UNIFORMS_GLSL
#define VISU_TONEMAP_UNIFORMS_GLSL
/**
 * ToneMapUniforms, uniform slot 0 of every pass in the tone-map chain (luma, coarse, reduce,
 * exposure, grid, blurs, upsample, resolve). Mirrors `ToneMapUniforms` in
 * src/graphics/deferred/tonemappass.eco; std140, vec4 members only. Each pass uploads its own
 * copy, so `u_tm_pass` carries the per-pass knobs (blur axis, sigma, radius, slices).
 */
layout(std140, set = 0, binding = 0) uniform ToneMapUniforms {
    // x EV used when y is 0 (and the compensation auto exposure adds to), y 1 reads the adapted
    // EV from the exposure texture, z 1 when the local operator runs, w the curve's linear
    // pre-exposure (ACES; 1 for the others, which the variant picks)
    vec4 u_tm_exposure;
    // x log2 midpoint (the key auto exposure puts a grey card at), y contrast above it,
    // z contrast below it, w detail kept
    vec4 u_tm_local;
    // x bilateral share of the base, y log2 at the grid's first slice, z stops the grid spans,
    // w slices
    vec4 u_tm_grid;
    // x luma width, y luma height, z scene width, w scene height
    vec4 u_tm_size;
    // filmic curve: x contrast (power), y shoulder, z b, w c (solved on the CPU)
    vec4 u_tm_curve;
    // rows of Rec.709 to the tone-map gamut, white balance folded in
    vec4 u_tm_in[3];
    // rows of the tone-map gamut back to Rec.709
    vec4 u_tm_out[3];
    // exposure: x strength, y min EV, z max EV, w log2 reference illuminance
    vec4 u_tm_adapt;
    // exposure: x highlight stops over the key, y highlight weight, z direct illuminance on the
    // ground (sun, moon, night ambient), w probe blend
    vec4 u_tm_meter;
    // exposure: x blend towards a brighter target this frame, y towards a darker one, z 1 when
    // last frame's EV is usable
    vec4 u_tm_history;
    // per pass: x axis (0 x, 1 y, 2 z), y sigma, z radius in taps, w slices of 64 x 32 cells
    vec4 u_tm_pass;
};

const vec3 TONEMAP_LUMA = vec3(0.2126, 0.7152, 0.0722);

// the EV this frame is exposed at: the adapted one from the exposure texel when auto exposure
// ran, else the fixed compensation (the texture is then white and never read)
float tonemap_ev(sampler2D exposure)
{
    if (u_tm_exposure.y > 0.5) {
        return texelFetch(exposure, ivec2(0), 0).r;
    }
    return u_tm_exposure.x;
}

// the luma image's size in texels
ivec2 tonemap_luma_size()
{
    return ivec2(u_tm_size.xy + 0.5);
}

// the luma texels [lo, hi) one of the 64 x 32 cells covers: at least one, at most 16 x 16
void tonemap_cell_span(ivec2 cell, ivec2 luma, out ivec2 lo, out ivec2 hi)
{
    lo = cell * luma / ivec2(64, 32);
    hi = max((cell + ivec2(1)) * luma / ivec2(64, 32), lo + ivec2(1));
    hi = min(hi, lo + ivec2(16));
}

#endif
