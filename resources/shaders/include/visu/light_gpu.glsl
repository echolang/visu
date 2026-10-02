/**
 * One light table row and the helpers both the cull kernels and the shading loop use.
 * Mirrors visu::graphics::LightGpu (std430, 80 bytes) and the LIGHT_* constants.
 */
#ifndef VISU_LIGHT_GPU_GLSL
#define VISU_LIGHT_GPU_GLSL

#define LIGHT_SLOT_BITS 13u
#define LIGHT_SLOT_MASK 0x1FFFu
#define LIGHT_ZBINS 64u
// the most visible lights one view keeps
#define LIGHT_VISIBLE_MAX 4096u

// the cull's counters: visible, visible dropped
#define LIGHT_COUNTER_VISIBLE 0u
#define LIGHT_COUNTER_DROPPED 1u
// one past the last sorted index within the shadow distance
#define LIGHT_COUNTER_SHADOWED 2u

struct LightGpu {
    // xyz world position, w radius (0: a free slot)
    vec4 position_radius;
    // rgb linear colour, w base intensity
    vec4 color_intensity;
    // x source radius, y 1 when it casts, z normal offset, w slope bias
    vec4 source;
    // x amplitude, y speed in radians a second, z phase, w a spot's cone offset
    vec4 flicker;
    // xyz a spot's world axis, w its cone scale; (0, 0, 0, 0) with offset 1 shines every way
    vec4 spot;
};

// how much of light `l` a spot sends along `fromLight` (unit, from the light outward): 1 inside
// the inner cone, 0 past the outer, a square ramp between. The CPU folds both cosines into a
// scale and an offset (`1 / (inner - outer)`, `-outer` times it), so this is one multiply-add; a
// light that shines every way has scale 0 and offset 1
float light_cone(LightGpu l, vec3 fromLight)
{
    float t = clamp(dot(l.spot.xyz, fromLight) * l.spot.w + l.flicker.w, 0.0, 1.0);
    return t * t;
}

float light_intensity(LightGpu l, float seconds)
{
    if (l.flicker.x <= 0.0) {
        return l.color_intensity.w;
    }
    return l.color_intensity.w + l.flicker.x * sin(l.flicker.y * seconds + l.flicker.z);
}

// the windowed inverse-square falloff of a light of reach `radius` at `dist`
float point_atten(float dist, float radius)
{
    float d = clamp(dist / max(radius, 1e-4), 0.0, 1.0);
    float window = clamp(1.0 - d * d * d * d, 0.0, 1.0);
    window = window * window;
    return window / (dist * dist + 1.0);
}

// the radiance light `l` sends to a point `dist` away, flicker included
vec3 light_radiance(LightGpu l, float dist, float seconds)
{
    return l.color_intensity.rgb * light_intensity(l, seconds) * point_atten(dist, l.position_radius.w);
}

// whether `l` casts and stands within the shadow distance `limit` of `eye`: the lights the
// shadow atlas keeps pages for
bool light_casts(LightGpu l, vec3 eye, float limit)
{
    return !(l.source.y < 0.5 || distance(l.position_radius.xyz, eye) > limit);
}

uint light_zslice(float viewDepth, vec4 clusterZ)
{
    float z = max(viewDepth, clusterZ.x);
    float s = log2(z / clusterZ.x) * clusterZ.y;
    return uint(clamp(s, 0.0, clusterZ.z - 1.0));
}

#endif
