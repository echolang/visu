/**
 * The air between a pixel and the eye, at uniform slot VISU_FOG_SLOT (3 unless a caller
 * overrides it). Two layers, applied in linear HDR before the tone map:
 *
 * - Height fog: a participating medium whose density falls off with height, lit by the sun,
 *   the moon and the sky's ambient through a phase function, so it glows toward a low sun,
 *   goes blue-grey in shade and moonlit at night. Extinction is grey, like mist.
 * - Aerial perspective: the atmosphere of `sky.glsl` itself, read from the aerial table
 *   (`visu/aerial.glsl`, bound at VISU_AERIAL_SLOT), per channel, so far ridges fade into
 *   the sky behind them. Sky pixels skip it: the sky already is the whole atmosphere.
 *
 * `u_fog_model.w` 0 is the fog visu had before (`--flag fog.model=legacy`): grey haze mixed
 * toward the fog's sky table (`visu/fog_sky.glsl`, at VISU_FOG_SKY_SLOT) with an analytic
 * glow. It stays until the new frame is signed off. Mirrors visu::graphics::FogUniforms. D0
 * (density at the camera) is collapsed on the CPU.
 */
#ifndef VISU_FOG_GLSL
#define VISU_FOG_GLSL

#ifndef VISU_FOG_SLOT
#define VISU_FOG_SLOT 3
#endif

#include "visu/phase.glsl"
#include "visu/aerial.glsl"
#include "visu/fog_sky.glsl"

layout(std140, set = 0, binding = VISU_FOG_SLOT) uniform FogUniforms {
    // x density at the camera (D0, 1/m), y height falloff k (1/m), z max opacity, w 1 enabled
    vec4 u_fog_density;
    // legacy: rgb inscattering colour or tint, w 1 multiplies the fog's sky table
    vec4 u_fog_color;
    // x start distance, y cutoff distance (0 none), z sky distance, w legacy directional start
    vec4 u_fog_params;
    // legacy: rgb directional inscattering colour (already sun tinted), w exponent
    vec4 u_fog_sun;
    // legacy: rgb added to the sky table's colour, the starlight the table has no stars for
    vec4 u_fog_floor;
    // legacy: rgb directional inscattering towards the moon (already moon tinted), w exponent
    vec4 u_fog_moon;
    // x shaft scatter, y glow occlusion, w 1 when the resolved shafts are bound
    vec4 u_fog_shafts;
    // rgb key light radiance for the shafts, w 1 when the moon is the key light
    vec4 u_fog_shaft_light;
    // x core anisotropy, y wide anisotropy, z wide lobe share
    vec4 u_fog_shaft_phase;
    // xyz unit vector towards the sun, w 1 the lit medium and the aerial perspective (0 legacy)
    vec4 u_fog_model;
    // xyz unit vector towards the moon, w share of the forward lobe in the medium's phase
    vec4 u_fog_to_moon;
    // rgb sun irradiance at the fog, w forward lobe anisotropy
    vec4 u_fog_sun_light;
    // rgb moon irradiance at the fog, w 1 while it casts any
    vec4 u_fog_moon_light;
    // rgb the sky's radiance the medium scatters evenly: the dome, the ground, the night floor
    vec4 u_fog_ambient;
    // rgb the medium's single-scattering albedo, w its multiple scattering stand-in
    vec4 u_fog_albedo;
    // z the sky's Mie anisotropy, w distance scale (0 no aerial perspective)
    vec4 u_fog_aerial;
    // rgb Rayleigh scattering, w Mie extinction (1/m): the transmittance of an aerial path
    vec4 u_fog_aerial_extinction;
};

#ifndef VISU_FOG_SKY_SLOT
#define VISU_FOG_SKY_SLOT 13
#endif

#ifndef VISU_AERIAL_SLOT
#define VISU_AERIAL_SLOT 14
#endif

layout(set = 1, binding = VISU_FOG_SKY_SLOT) uniform sampler2D u_fog_sky;

// the sky and the skybox fog only sky pixels, which take no aerial perspective, so they bind
// no table
#ifndef VISU_FOG_SKY_ONLY
layout(set = 1, binding = VISU_AERIAL_SLOT) uniform sampler2DArray u_aerial;
#endif

/**
 * Optical depth from the camera along a ray of length `len` with vertical
 * direction `dy`. Taylor around a horizontal ray; `x` is clamped so exp
 * stays finite on a long downward look.
 */
float fog_integral(float dy, float len)
{
    float k = u_fog_density.y;
    float d0 = u_fog_density.x;
    float x = max(k * dy * len, -60.0);

    if (abs(x) < 1e-4) {
        return d0 * len * (1.0 - 0.5 * x);
    }

    return d0 * (1.0 - exp(-x)) / (k * dy);
}

/**
 * Legacy inscattering colour along `dir`. Constant radiance when fromSky is off; otherwise the
 * sky at the horizon of this azimuth (lifted above the ground, the sun's azimuth straight up or
 * down) plus the night floor, tinted.
 */
vec3 fog_color(vec3 dir)
{
    vec3 tint = u_fog_color.rgb;

    if (u_fog_color.w < 0.5) {
        return tint;
    }

    vec2 uv = fog_sky_uv(fog_sky_horizon(dir, u_fog_model.xyz));
    return tint * (textureLod(u_fog_sky, uv, 0.0).rgb + u_fog_floor.rgb);
}

/**
 * The legacy fog: grey haze toward `fog_color`, the analytic glow on top.
 */
vec3 fog_apply_legacy(vec3 color, vec3 relative)
{
    if (u_fog_density.w < 0.5) {
        return color;
    }

    float len = length(relative);

    if (len < 1e-3) {
        return color;
    }

    float cutoff = u_fog_params.y;

    if (cutoff > 0.0 && len > cutoff) {
        return color;
    }

    vec3 dir = relative / len;
    float dy = dir.y;
    float start = u_fog_params.x;
    float optical = fog_integral(dy, len);
    float t = max(exp(-(optical - fog_integral(dy, min(len, start)))), 1.0 - u_fog_density.z);
    float td = exp(-(optical - fog_integral(dy, min(len, start + u_fog_params.w))));
    float sun = pow(max(dot(dir, u_fog_model.xyz), 0.0), u_fog_sun.w);
    float moon = pow(max(dot(dir, u_fog_to_moon.xyz), 0.0), max(u_fog_moon.w, 1.0));
    vec3 glow = u_fog_sun.rgb * sun + u_fog_moon.rgb * moon;
    vec3 fog = fog_color(dir) * (1.0 - t) + glow * (1.0 - td);
    return color * t + fog;
}

/**
 * The medium's phase: a forward Henyey-Greenstein lobe, its share `u_fog_to_moon.w`, over an
 * even one. Mist scatters many times, so it glows toward the light but never goes black away
 * from it.
 */
float fog_phase(float mu)
{
    float forward = phase_hg(u_fog_sun_light.w, mu);
    return mix(1.0 / (4.0 * PHASE_PI), forward, u_fog_to_moon.w);
}

/**
 * Radiance the medium sends along `-dir` per unit of opacity: the sun and the moon through
 * the phase, the sky's ambient evenly, all times the albedo and the multiple scattering
 * stand-in (single scattering alone leaves a haze well under the sky it hangs in). `lit_sun` / `lit_moon` are the
 * share of each light's path that is not in shadow (the god rays), 1 without them.
 */
vec3 fog_medium(vec3 dir, float lit_sun, float lit_moon)
{
    vec3 light = u_fog_ambient.rgb + u_fog_sun_light.rgb * (fog_phase(dot(dir, u_fog_model.xyz)) * lit_sun);

    // the moon only lights the fog while it is up, the same for every pixel
    if (u_fog_moon_light.w > 0.5) {
        light += u_fog_moon_light.rgb * (fog_phase(dot(dir, u_fog_to_moon.xyz)) * lit_moon);
    }

    return u_fog_albedo.rgb * (light * u_fog_albedo.w);
}

/**
 * The height fog over `color`, `len` metres along `dir`: `lit_*` as in `fog_medium`, `rays`
 * the shafts' own inscatter, added inside the fog.
 */
vec3 fog_height(vec3 color, vec3 dir, float len, float lit_sun, float lit_moon, vec3 rays)
{
    if (u_fog_density.w < 0.5) {
        return color;
    }

    float cutoff = u_fog_params.y;

    if (cutoff > 0.0 && len > cutoff) {
        return color;
    }

    float dy = dir.y;
    float start = u_fog_params.x;
    float optical = fog_integral(dy, len);
    float t = max(exp(-(optical - fog_integral(dy, min(len, start)))), 1.0 - u_fog_density.z);
    return color * t + fog_medium(dir, lit_sun, lit_moon) * (1.0 - t) + rays;
}

/**
 * One slice of the aerial table along `uv`: rgb the in-scattered light under this pixel's sun
 * phase, and the path's Rayleigh and Mie optical depth in `depth`.
 */
#ifndef VISU_FOG_SKY_ONLY
vec3 aerial_fetch(vec2 uv, float k, float mie_sun, out vec2 depth)
{
    vec2 at = aerial_atlas(uv, k);
    vec4 light = textureLod(u_aerial, vec3(at, 0.0), 0.0);
    vec4 sun_m = textureLod(u_aerial, vec3(at, 1.0), 0.0);
    depth = vec2(light.a, sun_m.a);
    return light.rgb + sun_m.rgb * mie_sun;
}
#endif

/**
 * The atmosphere between the eye and a point `len` metres along `dir`, over `color`: the two
 * slices around it, interpolated, the first against the empty air at the eye.
 */
vec3 aerial_apply(vec3 color, vec3 dir, float len)
{
#ifdef VISU_FOG_SKY_ONLY
    return color;
#else
    if (u_fog_aerial.w <= 0.0) {
        return color;
    }

    float s = min(aerial_slice(len * u_fog_aerial.w), AERIAL_SLICES - 1.0);
    float k = floor(s);
    float f = s - k;
    vec2 uv = aerial_uv(dir);
    float mie_sun = phase_mie(u_fog_aerial.z, dot(dir, u_fog_model.xyz));
    vec2 d_far;
    vec3 far = aerial_fetch(uv, min(k + 1.0, AERIAL_SLICES - 1.0), mie_sun, d_far);
    vec2 d_near = vec2(0.0);
    vec3 near = vec3(0.0);

    if (k >= 0.0) {
        near = aerial_fetch(uv, k, mie_sun, d_near);
    }

    vec2 depth = mix(d_near, d_far, f);
    vec3 transmittance = exp(-(u_fog_aerial_extinction.rgb * depth.x + vec3(u_fog_aerial_extinction.w) * depth.y));
    return color * transmittance + mix(near, far, f);
#endif
}

/**
 * Both layers over a surface at `relative` (the pixel minus the camera).
 */
vec3 fog_surface(vec3 color, vec3 relative, float lit_sun, float lit_moon, vec3 rays)
{
    float len = length(relative);

    if (len < 1e-3) {
        return color;
    }

    vec3 dir = relative / len;
    color = fog_height(color, dir, len, lit_sun, lit_moon, rays);
    return aerial_apply(color, dir, len);
}

/**
 * The fog over a surface at `relative`: early out when disabled, closer than a millimetre, or
 * past the cutoff.
 */
vec3 fog_apply(vec3 color, vec3 relative)
{
    if (u_fog_model.w < 0.5) {
        return fog_apply_legacy(color, relative);
    }

    return fog_surface(color, relative, 1.0, 1.0, vec3(0.0));
}

/**
 * Fog a sky / skybox pixel: the height fog out to the sky distance along `dir`. The sky
 * already holds the atmosphere, so there is no aerial perspective on it.
 */
vec3 fog_apply_sky(vec3 color, vec3 dir)
{
    vec3 d = normalize(dir);

    if (u_fog_model.w < 0.5) {
        return fog_apply_legacy(color, d * u_fog_params.z);
    }

    return fog_height(color, d, u_fog_params.z, 1.0, 1.0, vec3(0.0));
}

#ifdef VISU_FOG_RAYS
#include "visu/godrays.glsl"

/**
 * The key light's shafts at screen `uv`, marched to `fetchDist`: the lit share of its path in
 * x, the shafts' own inscatter along `dir` in yzw.
 */
vec4 fog_shafts(vec3 dir, vec2 uv, float fetchDist)
{
    vec2 shaft = godrays_fetch(uv, fetchDist);
    float lit = mix(1.0, shaft.y, u_fog_shafts.y);
    vec3 toLight = u_fog_shaft_light.w > 0.5 ? u_fog_to_moon.xyz : u_fog_model.xyz;
    float phase = godrays_phase2(dot(dir, toLight), u_fog_shaft_phase.xyz);
    return vec4(lit, u_fog_shaft_light.rgb * (phase * shaft.x * u_fog_shafts.x));
}

/**
 * `fog_apply` with this frame's light shafts at screen `uv`. Without them bound it is
 * `fog_apply` itself, so a frame with god rays off shades exactly as before.
 */
vec3 fog_apply_rays_at(vec3 color, vec3 relative, vec2 uv, float fetchDist);

vec3 fog_apply_rays(vec3 color, vec3 relative, vec2 uv)
{
    if (u_fog_shafts.w < 0.5) {
        return fog_apply(color, relative);
    }

    return fog_apply_rays_at(color, relative, uv, length(relative));
}

/**
 * The legacy shaft path: the directional glow dims by the shadowed share of its ray and the
 * key light's shadowed inscatter is added on top.
 */
vec3 fog_apply_rays_legacy(vec3 color, vec3 relative, vec2 uv, float fetchDist)
{

    if (u_fog_density.w < 0.5) {
        return color;
    }

    float len = length(relative);

    if (len < 1e-3) {
        return color;
    }

    float cutoff = u_fog_params.y;

    if (cutoff > 0.0 && len > cutoff) {
        return color;
    }

    vec3 dir = relative / len;
    float dy = dir.y;
    float start = u_fog_params.x;
    float optical = fog_integral(dy, len);
    float t = max(exp(-(optical - fog_integral(dy, min(len, start)))), 1.0 - u_fog_density.z);
    float td = exp(-(optical - fog_integral(dy, min(len, start + u_fog_params.w))));
    vec2 shaft = godrays_fetch(uv, fetchDist);
    float occlude = mix(1.0, shaft.y, u_fog_shafts.y);
    float sun = pow(max(dot(dir, u_fog_model.xyz), 0.0), u_fog_sun.w);
    float moon = pow(max(dot(dir, u_fog_to_moon.xyz), 0.0), max(u_fog_moon.w, 1.0));
    vec3 glow = (u_fog_sun.rgb * sun + u_fog_moon.rgb * moon) * occlude;
    vec3 fog = fog_color(dir) * (1.0 - t) + glow * (1.0 - td);
    vec3 toLight = u_fog_shaft_light.w > 0.5 ? u_fog_to_moon.xyz : u_fog_model.xyz;
    float phase = godrays_phase2(dot(dir, toLight), u_fog_shaft_phase.xyz);
    vec3 rays = u_fog_shaft_light.rgb * (phase * shaft.x * u_fog_shafts.x);
    return color * t + fog + rays;
}

/**
 * The shaft path proper. `fetchDist` is the distance the shaft texels were marched to for
 * this pixel: its own for geometry, the march's sky sentinel for the sky. The lit share of
 * the key light's path dims its light in the medium; the shafts' inscatter adds on top.
 */
vec3 fog_apply_rays_at(vec3 color, vec3 relative, vec2 uv, float fetchDist)
{
    if (u_fog_model.w < 0.5) {
        return fog_apply_rays_legacy(color, relative, uv, fetchDist);
    }

    float len = length(relative);

    if (len < 1e-3) {
        return color;
    }

    vec3 dir = relative / len;
    vec4 shafts = fog_shafts(dir, uv, fetchDist);
    bool moonKey = u_fog_shaft_light.w > 0.5;
    float lit_sun = moonKey ? 1.0 : shafts.x;
    float lit_moon = moonKey ? shafts.x : 1.0;
    return fog_surface(color, relative, lit_sun, lit_moon, shafts.yzw);
}

/**
 * `fog_apply_sky` with the shafts.
 */
vec3 fog_apply_sky_rays(vec3 color, vec3 dir, vec2 uv)
{
    if (u_fog_shafts.w < 0.5) {
        return fog_apply_sky(color, dir);
    }

    vec3 d = normalize(dir);

    if (u_fog_model.w < 0.5) {
        return fog_apply_rays_legacy(color, d * u_fog_params.z, uv, GODRAY_SKY_DEPTH);
    }

    vec4 shafts = fog_shafts(d, uv, GODRAY_SKY_DEPTH);
    bool moonKey = u_fog_shaft_light.w > 0.5;
    float lit_sun = moonKey ? 1.0 : shafts.x;
    float lit_moon = moonKey ? shafts.x : 1.0;
    return fog_height(color, d, u_fog_params.z, lit_sun, lit_moon, shafts.yzw);
}
#endif

#endif
