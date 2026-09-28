/**
 * Procedural atmosphere at uniform slot 2: single-scattering Rayleigh
 * and Mie along the view ray under the sun and the moon, a ground
 * hemisphere below the horizon, an optional sun disk, and an optional
 * moon disc and star field. Mirrors visu::graphics::SkyUniforms.
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
    // xyz unit vector towards the moon, w moon light the atmosphere scatters (0 none)
    vec4 u_sky_moon;
    // x illumination, y earthshine, z cos of the disc radius, w star brightness
    vec4 u_sky_moon_params;
    // rgb moon tint, w 1 draws the moon disc and the stars
    vec4 u_sky_moon_color;
};

const float SKY_PI = 3.14159265359;
// angular radius of the solar disk, radians (0.2665 degrees)
const float SKY_SUN_RADIUS = 0.004652;
// soft edge on the disk, radians (0.05 degrees)
const float SKY_SUN_EDGE = 0.00087;
// single scattering alone leaves the dome about a quarter as bright as a real sky
// against the same sun; this stands in for the missing multiple scattering
const float SKY_MULTIPLE_SCATTERING = 4.0;
// radiance of the fully lit moon disc before transmittance; tonemaps close to white
const float SKY_MOON_RADIANCE = 2.2;
// soft edge on the moon disc as a fraction of its radius
const float SKY_MOON_EDGE = 0.06;
// angular falloff of the glow around the moon, radians, and its strength per unit moon light
const float SKY_MOON_HALO_WIDTH = 0.045;
const float SKY_MOON_HALO = 0.35;
// star grid cells across a unit direction; a cell is about eight pixels at 1440p
const float SKY_STAR_CELLS = 180.0;
// share of cells that hold a star
const float SKY_STAR_DENSITY = 0.045;
// sine of the sun elevation where night starts to fall and where it is complete;
// mirrors MOON_DUSK_START / MOON_DUSK_END in visu::graphics (moon.eco)
const float SKY_DUSK_START = 0.035;
const float SKY_DUSK_END = -0.14;

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
 * The view march without its phase functions: what the sun and the moon scatter towards the
 * observer along `dir`, split into Rayleigh and Mie so a caller can apply the phase per
 * pixel. `sun_r` / `moon_r` carry the Rayleigh scattering coefficient, `sun_m` / `moon_m`
 * the Mie one; the light intensities, the multiple scattering stand-in and the moon tint are
 * left to the caller. The phase is constant along a ray, so nothing is lost by the split.
 */
struct SkyScatter {
    vec3 sun_r;
    vec3 sun_m;
    vec3 moon_r;
    vec3 moon_m;
    vec3 transmittance;
    float t_ground;
};

SkyScatter sky_scatter_n(vec3 dir, int view_samples, int light_samples)
{
    vec3 o = sky_observer();
    float rg = u_sky_params.z;
    float rt = u_sky_params.w;
    vec2 atmo = sky_ray_sphere(o, dir, rt);
    float t_max = max(atmo.y, 0.0);
    vec2 ground = sky_ray_sphere(o, dir, rg);
    SkyScatter s;
    s.t_ground = -1.0;

    if (ground.x > 0.0) {
        s.t_ground = ground.x;
        t_max = ground.x;
    }

    float step_len = t_max / float(view_samples);
    vec3 to_sun = u_sky_sun.xyz;
    vec2 scale = vec2(u_sky_rayleigh.w, u_sky_mie.w);
    vec3 sum_r = vec3(0.0);
    vec3 sum_m = vec3(0.0);
    vec2 depth_view = vec2(0.0);
    // the moon shares the view march; its light loop only runs while it is up and lit,
    // which is the same for every pixel of the draw
    bool moon_on = u_sky_moon.w > 0.0;
    vec3 to_moon = u_sky_moon.xyz;
    vec3 moon_r = vec3(0.0);
    vec3 moon_m = vec3(0.0);

    for (int i = 0; i < view_samples; i++) {
        vec3 p = o + dir * ((float(i) + 0.5) * step_len);
        float h = max(length(p) - rg, 0.0);
        vec2 dens = exp(-h / scale) * step_len;
        depth_view += dens;

        if (moon_on && sky_ray_sphere(p, to_moon, rg).x <= 0.0) {
            vec2 moon_atmo = sky_ray_sphere(p, to_moon, rt);
            vec2 moon_depth = sky_optical_depth(p, to_moon, max(moon_atmo.y, 0.0), light_samples);
            vec3 tm = sky_extinction(depth_view + moon_depth);
            moon_r += tm * dens.x;
            moon_m += tm * dens.y;
        }

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

    s.transmittance = sky_extinction(depth_view);
    s.sun_r = sum_r * u_sky_rayleigh.xyz;
    s.sun_m = sum_m * vec3(u_sky_mie.x);
    s.moon_r = moon_r * u_sky_rayleigh.xyz;
    s.moon_m = moon_m * vec3(u_sky_mie.x);
    return s;
}

float sky_phase_rayleigh(float mu)
{
    return 3.0 / (16.0 * SKY_PI) * (1.0 + mu * mu);
}

float sky_phase_mie(float mu)
{
    float g = u_sky_mie.z;
    float gg = g * g;
    return 3.0 / (8.0 * SKY_PI) * ((1.0 - gg) * (1.0 + mu * mu))
        / ((2.0 + gg) * pow(1.0 + gg - 2.0 * g * mu, 1.5));
}

/**
 * Radiance of a split march seen along `dir`: each part under its own phase, the lights'
 * intensities and the moon tint applied.
 */
vec3 sky_scatter_color(vec3 dir, vec3 sun_r, vec3 sun_m, vec3 moon_r, vec3 moon_m)
{
    float mu = dot(dir, u_sky_sun.xyz);
    vec3 color = (u_sky_sun.w * SKY_MULTIPLE_SCATTERING)
        * (sun_r * sky_phase_rayleigh(mu) + sun_m * sky_phase_mie(mu));

    if (u_sky_moon.w > 0.0) {
        float mu_m = dot(dir, u_sky_moon.xyz);
        color += (u_sky_moon.w * SKY_MULTIPLE_SCATTERING) * u_sky_moon_color.rgb
            * (moon_r * sky_phase_rayleigh(mu_m) + moon_m * sky_phase_mie(mu_m));
    }

    return color;
}

/**
 * In-scattered light along `dir` up to the atmosphere edge or the ground,
 * whichever comes first. `transmittance` is what survives that path and
 * `t_ground` the ground hit distance (negative when the ray misses it).
 * Sample counts are arguments so fog can reuse this at a lower quality.
 */
vec3 sky_inscatter_n(vec3 dir, int view_samples, int light_samples, out vec3 transmittance, out float t_ground)
{
    SkyScatter s = sky_scatter_n(dir, view_samples, light_samples);
    transmittance = s.transmittance;
    t_ground = s.t_ground;
    return sky_scatter_color(dir, s.sun_r, s.sun_m, s.moon_r, s.moon_m);
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

float sky_hash(vec3 p)
{
    p = fract(p * vec3(0.1031, 0.1030, 0.0973));
    p += dot(p, p.yxz + 33.33);
    return fract((p.x + p.y) * p.z);
}

vec3 sky_hash3(vec3 p)
{
    return vec3(sky_hash(p), sky_hash(p + 17.13), sky_hash(p + 41.71));
}

float sky_value_noise(vec2 x)
{
    vec2 i = floor(x);
    vec2 f = fract(x);
    f = f * f * (3.0 - 2.0 * f);
    float a = sky_hash(vec3(i, 0.0));
    float b = sky_hash(vec3(i + vec2(1.0, 0.0), 0.0));
    float c = sky_hash(vec3(i + vec2(0.0, 1.0), 0.0));
    float d = sky_hash(vec3(i + vec2(1.0, 1.0), 0.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

/**
 * Moon disc seen through `transmittance`. The disc is a sphere lit from the sun
 * direction, so the terminator follows the true phase; the unlit side keeps a
 * little earthshine. Zero off the disc.
 */
vec3 sky_moon_disk(vec3 dir, vec3 transmittance)
{
    vec3 m = u_sky_moon.xyz;
    float c = dot(dir, m);
    float cr = u_sky_moon_params.z;

    if (c <= cr) {
        return vec3(0.0);
    }

    vec3 side = cross(m, vec3(0.0, 1.0, 0.0));

    if (dot(side, side) < 1e-6) {
        side = vec3(1.0, 0.0, 0.0);
    }

    vec3 right = normalize(side);
    vec3 up = cross(right, m);
    float radius = sqrt(max(1.0 - cr * cr, 1e-8));
    vec2 q = vec2(dot(dir, right), dot(dir, up)) / radius;
    float rr = dot(q, q);

    if (rr >= 1.0) {
        return vec3(0.0);
    }

    float edge = 1.0 - smoothstep(1.0 - SKY_MOON_EDGE, 1.0, sqrt(rr));
    // the face turned towards the observer, lit from where the sun is
    vec3 n = right * q.x + up * q.y - m * sqrt(1.0 - rr);
    float lit = max(dot(n, u_sky_sun.xyz), 0.0);
    float maria = sky_value_noise(q * 2.2 + 3.1) * 0.6 + sky_value_noise(q * 6.0 + 11.7) * 0.3
        + sky_value_noise(q * 15.0 + 5.3) * 0.1;
    float albedo = mix(0.45, 1.0, smoothstep(0.38, 0.62, maria));
    float limb = 0.75 + 0.25 * sqrt(1.0 - rr);
    vec3 tint = mix(vec3(1.0), u_sky_moon_color.rgb, 0.35);
    float light = lit * limb + u_sky_moon_params.y;
    return transmittance * tint * (SKY_MOON_RADIANCE * albedo * light * edge);
}

/**
 * Soft glow around the moon, scaled by the light it casts, so a full moon lights the
 * haze around it and a thin crescent barely does. One dot product a pixel.
 */
vec3 sky_moon_halo(vec3 dir, vec3 transmittance)
{
    float c = clamp(dot(dir, u_sky_moon.xyz), -1.0, 1.0);

    if (c <= 0.0 || u_sky_moon.w <= 0.0) {
        return vec3(0.0);
    }

    float angle = sqrt(max(2.0 * (1.0 - c), 0.0));
    return transmittance * u_sky_moon_color.rgb * (u_sky_moon.w * SKY_MOON_HALO * exp(-angle / SKY_MOON_HALO_WIDTH));
}

/**
 * Fixed stars: one hashed point per grid cell on the view direction, a few
 * percent of cells lit. They come out as the sun sets and
 * drown in a bright sky, so a moonlit dome keeps only the brightest. The fade
 * band is the renderer's night band, the one the night ambient uses.
 */
vec3 sky_stars(vec3 dir, vec3 transmittance, vec3 sky)
{
    // smoothstep needs edge0 < edge1, so fade in as one minus the rise
    float fade = (1.0 - smoothstep(SKY_DUSK_END, SKY_DUSK_START, u_sky_sun.y)) * u_sky_moon_params.w;

    if (fade <= 0.0 || dir.y <= 0.0) {
        return vec3(0.0);
    }

    vec3 p = dir * SKY_STAR_CELLS;
    vec3 cell = floor(p);
    float h = sky_hash(cell);

    if (h > SKY_STAR_DENSITY) {
        return vec3(0.0);
    }

    vec3 at = cell + 0.2 + 0.6 * sky_hash3(cell + 5.0);
    float d = length(p - at);
    float core = exp(-d * d * 60.0);
    // brightness follows a steep power law: many faint stars, a few bright ones
    float mag = pow(h / SKY_STAR_DENSITY, 6.0) * 3.5 + 0.12;
    float warm = sky_hash(cell + 9.0);
    vec3 color = mix(vec3(0.75, 0.85, 1.0), vec3(1.0, 0.85, 0.65), warm);
    float lum = dot(sky, vec3(0.2126, 0.7152, 0.0722));
    float drown = exp(-lum * 60.0);
    return transmittance * color * (core * mag * fade * drown);
}

/**
 * The sharp things in the sky over `color`, the atmosphere along `dir`: the sun disk, and
 * the moon's halo, disc and the stars when they are drawn. Per pixel, never baked: none of
 * them survives a table lookup.
 */
vec3 sky_lights(vec3 dir, vec3 transmittance, vec3 color)
{
    if (u_sky_origin.w > 0.5) {
        color += sky_sun_disk(dir, transmittance);
    }

    if (u_sky_moon_color.w > 0.5) {
        vec3 sky = color;
        color += sky_moon_halo(dir, transmittance);
        color += sky_moon_disk(dir, transmittance);
        color += sky_stars(dir, transmittance, sky);
    }

    return color;
}

/**
 * The ground `t_ground` metres along `dir`: lambert under the attenuated sun and moon plus
 * half the sky mirrored up. Radiance leaving the ground, before the transmittance back to
 * the observer.
 */
vec3 sky_ground(vec3 dir, float t_ground)
{
    vec3 p = sky_observer() + dir * t_ground;
    vec3 n = normalize(p);
    vec3 to_sun = u_sky_sun.xyz;
    vec3 sun = sky_transmittance_from(p, to_sun) * (u_sky_sun.w * max(dot(n, to_sun), 0.0) / SKY_PI);

    if (u_sky_moon.w > 0.0) {
        vec3 to_moon = u_sky_moon.xyz;
        sun += sky_transmittance_from(p, to_moon) * u_sky_moon_color.rgb
            * (u_sky_moon.w * max(dot(n, to_moon), 0.0) / SKY_PI);
    }
    vec3 up_transmittance;
    float up_ground;
    vec3 mirrored = reflect(dir, n);
    vec3 ambient = 0.5 * sky_inscatter(mirrored, up_transmittance, up_ground);
    return u_sky_ground.xyz * (sun + ambient);
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
        return sky_lights(dir, transmittance, color) * u_sky_ground.w;
    }

    vec3 ground = sky_ground(dir, t_ground);
    return (color + transmittance * ground) * u_sky_ground.w;
}

#endif
