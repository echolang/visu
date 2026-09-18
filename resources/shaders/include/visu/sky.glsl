/**
 * Procedural atmosphere at uniform slot 2: single-scattering Rayleigh
 * and Mie along the view ray, a ground hemisphere below the horizon,
 * and an optional sun disk. Mirrors visu::graphics::SkyUniforms.
 *
 * The same function feeds the per-pixel background, the probe bake
 * and any forward-lit geometry drawn into the probe, so they agree.
 * Radiance is linear HDR; callers clamp to the half-float range.
 */
#ifndef VISU_SKY_GLSL
#define VISU_SKY_GLSL

#ifndef VISU_SKY_SLOT
#define VISU_SKY_SLOT 2
#endif

layout(std140, set = 0, binding = VISU_SKY_SLOT) uniform SkyUniforms {
    // xyz unit vector towards the sun, w sun intensity
    vec4 u_sky_sun;
    // xyz observer world position in metres (y up), w 1 draws the sun disk
    vec4 u_sky_origin;
    // xyz rayleigh scattering (1/m), w rayleigh scale height (m)
    vec4 u_sky_rayleigh;
    // x mie scattering, y mie extinction (1/m), z anisotropy g, w mie scale height (m)
    vec4 u_sky_mie;
    // xyz ground albedo, w exposure
    vec4 u_sky_ground;
    // x view samples, y light samples, z planet radius, w atmosphere radius (m)
    vec4 u_sky_params;
};

const float SKY_PI = 3.14159265359;
// angular radius of the solar disk, radians (0.2665 degrees)
const float SKY_SUN_RADIUS = 0.004652;
// soft edge on the disk, radians (0.05 degrees)
const float SKY_SUN_EDGE = 0.00087;
// single scattering alone leaves the dome about a quarter as bright as a real sky
// against the same sun; this stands in for the missing multiple scattering
const float SKY_MULTIPLE_SCATTERING = 4.0;

/**
 * Ray against a sphere at the origin: (entry, exit) distances, both
 * negative when the sphere is missed or lies behind.
 */
vec2 sky_ray_sphere(vec3 o, vec3 d, float r)
{
    float b = dot(o, d);
    float c = dot(o, o) - r * r;
    float disc = b * b - c;

    if (disc < 0.0) {
        return vec2(-1.0, -1.0);
    }

    float s = sqrt(disc);
    return vec2(-b - s, -b + s);
}

/**
 * Observer in planet space: on the +Y axis, at least a metre off the ground.
 */
vec3 sky_observer()
{
    return vec3(0.0, u_sky_params.z + max(u_sky_origin.y, 1.0), 0.0);
}

/**
 * Rayleigh and Mie optical depth along `len` metres from `p`.
 */
vec2 sky_optical_depth(vec3 p, vec3 d, float len, int samples)
{
    float step_len = len / float(samples);
    vec2 depth = vec2(0.0);
    vec2 scale = vec2(u_sky_rayleigh.w, u_sky_mie.w);

    for (int i = 0; i < samples; i++) {
        vec3 s = p + d * ((float(i) + 0.5) * step_len);
        float h = max(length(s) - u_sky_params.z, 0.0);
        depth += exp(-h / scale) * step_len;
    }

    return depth;
}

vec3 sky_extinction(vec2 depth)
{
    return exp(-(u_sky_rayleigh.xyz * depth.x + vec3(u_sky_mie.y) * depth.y));
}

/**
 * Transmittance from `p` to the sun; zero when the planet is in the way.
 */
vec3 sky_transmittance_from(vec3 p, vec3 to_sun)
{
    vec2 ground = sky_ray_sphere(p, to_sun, u_sky_params.z);

    if (ground.x > 0.0) {
        return vec3(0.0);
    }

    vec2 atmo = sky_ray_sphere(p, to_sun, u_sky_params.w);
    vec2 depth = sky_optical_depth(p, to_sun, max(atmo.y, 0.0), int(u_sky_params.y));
    return sky_extinction(depth);
}

/**
 * Transmittance from the observer towards the sun. Tints the direct light.
 */
vec3 sky_transmittance(vec3 to_sun)
{
    return sky_transmittance_from(sky_observer(), to_sun);
}

/**
 * In-scattered light along `dir` up to the atmosphere edge or the ground,
 * whichever comes first. `transmittance` is what survives that path and
 * `t_ground` the ground hit distance (negative when the ray misses it).
 * Sample counts are arguments so fog can reuse this at a lower quality.
 */
vec3 sky_inscatter_n(vec3 dir, int view_samples, int light_samples, out vec3 transmittance, out float t_ground)
{
    vec3 o = sky_observer();
    float rg = u_sky_params.z;
    float rt = u_sky_params.w;
    vec2 atmo = sky_ray_sphere(o, dir, rt);
    float t_max = max(atmo.y, 0.0);
    vec2 ground = sky_ray_sphere(o, dir, rg);
    t_ground = -1.0;

    if (ground.x > 0.0) {
        t_ground = ground.x;
        t_max = ground.x;
    }

    float step_len = t_max / float(view_samples);
    vec3 to_sun = u_sky_sun.xyz;
    float mu = dot(dir, to_sun);
    float g = u_sky_mie.z;
    float gg = g * g;
    float phase_r = 3.0 / (16.0 * SKY_PI) * (1.0 + mu * mu);
    float phase_m = 3.0 / (8.0 * SKY_PI) * ((1.0 - gg) * (1.0 + mu * mu))
        / ((2.0 + gg) * pow(1.0 + gg - 2.0 * g * mu, 1.5));
    vec2 scale = vec2(u_sky_rayleigh.w, u_sky_mie.w);
    vec3 sum_r = vec3(0.0);
    vec3 sum_m = vec3(0.0);
    vec2 depth_view = vec2(0.0);

    for (int i = 0; i < view_samples; i++) {
        vec3 p = o + dir * ((float(i) + 0.5) * step_len);
        float h = max(length(p) - rg, 0.0);
        vec2 dens = exp(-h / scale) * step_len;
        depth_view += dens;

        // the planet shadows this sample
        vec2 sun_ground = sky_ray_sphere(p, to_sun, rg);
        if (sun_ground.x > 0.0) {
            continue;
        }

        vec2 sun_atmo = sky_ray_sphere(p, to_sun, rt);
        vec2 depth_light = sky_optical_depth(p, to_sun, max(sun_atmo.y, 0.0), light_samples);
        vec3 t = sky_extinction(depth_view + depth_light);
        sum_r += t * dens.x;
        sum_m += t * dens.y;
    }

    transmittance = sky_extinction(depth_view);
    return (u_sky_sun.w * SKY_MULTIPLE_SCATTERING)
        * (sum_r * u_sky_rayleigh.xyz * phase_r + sum_m * vec3(u_sky_mie.x) * phase_m);
}

vec3 sky_inscatter(vec3 dir, out vec3 transmittance, out float t_ground)
{
    return sky_inscatter_n(dir, int(u_sky_params.x), int(u_sky_params.y), transmittance, t_ground);
}

/**
 * Sun disk with limb darkening, seen through `transmittance`. Zero off the disk.
 */
vec3 sky_sun_disk(vec3 dir, vec3 transmittance)
{
    vec3 to_sun = u_sky_sun.xyz;

    if (dot(dir, to_sun) <= 0.0) {
        return vec3(0.0);
    }

    // sine of the angle is the angle for something this small
    float angle = length(cross(dir, to_sun));
    float disk = 1.0 - smoothstep(SKY_SUN_RADIUS - SKY_SUN_EDGE, SKY_SUN_RADIUS, angle);

    if (disk <= 0.0) {
        return vec3(0.0);
    }

    float x = min(angle / SKY_SUN_RADIUS, 1.0);
    float limb = 1.0 - 0.6 * (1.0 - sqrt(max(1.0 - x * x, 0.0)));
    return transmittance * (u_sky_sun.w * 500.0 * disk * limb);
}

/**
 * Radiance arriving from `dir`: sky, or sunlit ground with aerial perspective
 * below the horizon. Multiplied by the exposure knob.
 */
vec3 sky_radiance(vec3 dir)
{
    vec3 transmittance;
    float t_ground;
    vec3 color = sky_inscatter(dir, transmittance, t_ground);

    if (t_ground < 0.0) {
        if (u_sky_origin.w > 0.5) {
            color += sky_sun_disk(dir, transmittance);
        }

        return color * u_sky_ground.w;
    }

    // the ground: lambert under the attenuated sun plus half the sky mirrored up
    vec3 p = sky_observer() + dir * t_ground;
    vec3 n = normalize(p);
    vec3 to_sun = u_sky_sun.xyz;
    vec3 sun = sky_transmittance_from(p, to_sun) * (u_sky_sun.w * max(dot(n, to_sun), 0.0) / SKY_PI);
    vec3 up_transmittance;
    float up_ground;
    vec3 mirrored = reflect(dir, n);
    vec3 ambient = 0.5 * sky_inscatter(mirrored, up_transmittance, up_ground);
    vec3 ground = u_sky_ground.xyz * (sun + ambient);
    return (color + transmittance * ground) * u_sky_ground.w;
}

#endif
