/**
 * Exponential height fog at uniform slot VISU_FOG_SLOT (3 unless a caller
 * overrides it). Density falls off with height, colour is either a constant
 * radiance or the atmosphere's horizon in the pixel's azimuth, and a
 * directional term glows towards the sun. Applied in linear HDR before
 * tonemap. Mirrors visu::graphics::FogUniforms. D0 (density at the camera)
 * is collapsed on the CPU.
 */
#ifndef VISU_FOG_GLSL
#define VISU_FOG_GLSL

#ifndef VISU_FOG_SLOT
#define VISU_FOG_SLOT 3
#endif

#include "visu/sky.glsl"

layout(std140, set = 0, binding = VISU_FOG_SLOT) uniform FogUniforms {
    // x density at the camera (D0, 1/m), y height falloff k (1/m), z max opacity, w 1 enabled
    vec4 u_fog_density;
    // rgb inscattering colour or tint, w 1 multiplies the atmosphere's horizon radiance
    vec4 u_fog_color;
    // x start distance, y cutoff distance (0 none), z sky distance, w directional start distance
    vec4 u_fog_params;
    // rgb directional inscattering colour (already sun tinted), w exponent
    vec4 u_fog_sun;
    // x sky view samples, y sky light samples
    vec4 u_fog_samples;
};

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
 * Horizon direction in `dir`'s azimuth, lifted to at least y = 0.02 so the
 * atmosphere sample sits above the ground. Straight up or down has no
 * azimuth: fall back to the sun, then +X.
 */
vec3 fog_horizon_dir(vec3 dir)
{
    vec2 xz = dir.xz;
    float horiz = length(xz);

    if (horiz < 1e-4) {
        xz = u_sky_sun.xz;
        horiz = length(xz);

        if (horiz < 1e-4) {
            xz = vec2(1.0, 0.0);
            horiz = 1.0;
        }
    }

    xz /= horiz;
    return normalize(vec3(xz.x, max(dir.y, 0.02), xz.y));
}

/**
 * Inscattering colour along `dir`. Constant radiance when fromSky is off;
 * otherwise the atmosphere at the horizon of this azimuth, tinted.
 */
vec3 fog_color(vec3 dir)
{
    vec3 tint = u_fog_color.rgb;

    if (u_fog_color.w < 0.5) {
        return tint;
    }

    vec3 transmittance;
    float t_ground;
    vec3 radiance = sky_inscatter_n(
        fog_horizon_dir(dir),
        int(u_fog_samples.x),
        int(u_fog_samples.y),
        transmittance,
        t_ground
    );
    return tint * u_sky_ground.w * radiance;
}

/**
 * Mix `color` with height fog. `relative` is the pixel position minus the
 * camera. Early-out when disabled, closer than a millimetre, or past the
 * cutoff. Directional inscattering has no opacity floor.
 */
vec3 fog_apply(vec3 color, vec3 relative)
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
    float sun = pow(max(dot(dir, u_sky_sun.xyz), 0.0), u_fog_sun.w);
    vec3 fog = fog_color(dir) * (1.0 - t) + u_fog_sun.rgb * sun * (1.0 - td);
    return color * t + fog;
}

/**
 * Fog a sky / skybox pixel: integrate out to the sky distance along `dir`.
 */
vec3 fog_apply_sky(vec3 color, vec3 dir)
{
    vec3 d = normalize(dir);
    return fog_apply(color, d * u_fog_params.z);
}

#endif
