/**
 * Parallax occlusion mapping: march the view ray down through a height field and return the uv
 * where it meets the relief. The includer defines the field before or after the include:
 *
 *     float parallax_height(vec2 uv, vec2 dx, vec2 dy);
 *
 * It returns 0..1, 1 the top of the relief. The march takes a varying number of steps, so
 * implicit derivatives are undefined inside it: sample with textureGrad and the caller's dx/dy,
 * taken from the unshifted uv before the march.
 *
 * `view_ts` is the unit vector from the surface to the eye in the uv's tangent frame (x along
 * +u, y along +v, z along the normal). `depth` is the relief at height 0 in uv units.
 */
#ifndef VISU_PARALLAX_GLSL
#define VISU_PARALLAX_GLSL

// the most steps any caller may ask for
#define PARALLAX_MAX_STEPS 64

float parallax_height(vec2 uv, vec2 dx, vec2 dy);

// tangent-frame view vector from an orthonormal t, b, n basis
vec3 parallax_view(vec3 t, vec3 b, vec3 n, vec3 to_eye)
{
    return vec3(dot(to_eye, t), dot(to_eye, b), dot(to_eye, n));
}

// relief multiplier: 1 up close, 0 from `fade` metres on, a quarter of the way to blend
float parallax_fade(float dist, float fade)
{
    return 1.0 - smoothstep(0.75 * fade, fade, dist);
}

vec2 parallax_offset(vec2 uv, vec3 view_ts, float depth, float max_steps, vec2 dx, vec2 dy)
{
    // a head-on view crosses the relief in few texels, a grazing one in many
    float head_on = clamp(view_ts.z, 0.0, 1.0);
    float top = clamp(max_steps, 1.0, float(PARALLAX_MAX_STEPS));
    float steps = floor(mix(top, max(4.0, top * 0.25), head_on));
    float layer = 1.0 / steps;
    // the floor on z keeps a grazing ray from sliding across whole tiles
    vec2 step_uv = (view_ts.xy / max(view_ts.z, 0.2)) * (depth * layer);

    vec2 at = uv;
    float ray = 1.0;
    float h = parallax_height(at, dx, dy);
    float prev_h = h;
    float prev_ray = ray;
    for (int i = 0; i < PARALLAX_MAX_STEPS; i++) {
        if (float(i) >= steps || ray <= h) {
            break;
        }
        prev_h = h;
        prev_ray = ray;
        at -= step_uv;
        ray -= layer;
        h = parallax_height(at, dx, dy);
    }

    // the zero crossing between the last sample above the relief and the first one below
    float below = h - ray;
    float above = prev_h - prev_ray;
    float w = below / max(below - above, 1e-5);
    return mix(at, at + step_uv, w);
}

#endif
