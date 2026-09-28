#version 450

// Light-shaft march at shaft resolution. Each texel walks its view ray through the height
// fog against the key light's cascades and writes (S, visible share, distance, 1): S is the
// shadowed, transmitted optical depth of the marched part, the visible share is the lit
// fraction of that same near segment, and the distance feeds the resolve and the bilateral
// upsample. One point tap per step; the resolve accumulates the jitter.

layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 frag_rays;

#include "visu/godrays_uniforms.glsl"
#include "visu/shadow.glsl"

layout(set = 1, binding = 0) uniform sampler2D gbuffer_position;
layout(set = 1, binding = 11) uniform sampler2DArray shadowmap;

// light-space depth slack so a lit surface does not shadow the air right above it
#define GODRAY_BIAS 0.0015

// e^{-tau} from the eye to distance t along a ray of vertical direction dy
float godrays_transmittance(float dy, float t)
{
    float k = u_gr_medium.x;
    float d0 = u_gr_march.w;
    float x = max(k * dy * t, -60.0);
    float optical = abs(x) < 1e-4 ? d0 * t * (1.0 - 0.5 * x) : d0 * (1.0 - exp(-x)) / (k * dy);
    return exp(-optical);
}

// interleaved gradient noise: a per-pixel offset the frame jitter walks
float godrays_ign(vec2 pixel)
{
    return fract(52.9829189 * fract(dot(pixel, vec2(0.06711056, 0.00583715))));
}

void main()
{
    ivec2 full = textureSize(gbuffer_position, 0);
    ivec2 px = clamp(ivec2(v_uv * vec2(full)), ivec2(0), full - ivec2(1));
    vec4 pos = texelFetch(gbuffer_position, px, 0);
    vec3 dir = godrays_view_dir(v_uv);
    float dist = GODRAY_SKY_DEPTH;
    if (pos.a >= 0.5) {
        dist = min(length(pos.xyz), GODRAY_SKY_DEPTH);
    }

    // view Z grows linearly along the ray, so the far cascade edge is a distance
    vec3 viewZ = vec3(u_view[0][2], u_view[1][2], u_view[2][2]);
    float zRate = dot(dir, viewZ);
    float tMax = min(dist, u_gr_march.y);
    if (zRate < -1e-4) {
        tMax = min(tMax, u_gr_key.w / zRate);
    }
    tMax = max(tMax, 0.0);

    // the plain fog leaves the air nearer than its start distance clear; so do the shafts
    float tStart = min(u_gr_prev_camera.w, tMax);
    int steps = int(u_gr_march.x + 0.5);
    float dt = (tMax - tStart) / float(steps);
    float jitter = fract(godrays_ign(gl_FragCoord.xy) + u_gr_march.z);
    float dy = dir.y;
    float d0 = u_gr_march.w;
    float k = u_gr_medium.x;

    float lit = 0.0;
    float total = 0.0;
    int cascade = -1;
    vec4 origin = vec4(0.0);
    vec4 along = vec4(0.0);
    for (int i = 0; i < GODRAY_MAX_STEPS; ++i) {
        if (i >= steps) {
            break;
        }
        float t = tStart + (float(i) + jitter) * dt;
        int c = csm_index(zRate * t, u_gr_splits);
        // the light-space position is affine in t: transform once per cascade, then step
        if (c != cascade) {
            cascade = c;
            origin = u_gr_light_space[c] * vec4(u_camera_position.xyz, 1.0);
            along = u_gr_light_space[c] * vec4(dir, 0.0);
        }
        vec4 clip = origin + along * t;
        vec3 proj = clip.xyz / max(clip.w, 1e-6);
        vec2 suv = uv_from_ndc(proj.xy);
        float vis = 1.0;
        if (suv.x >= 0.0 && suv.x <= 1.0 && suv.y >= 0.0 && suv.y <= 1.0 && proj.z <= 1.0) {
            float closest = texture(shadowmap, vec3(suv, float(c))).r;
            vis = proj.z - GODRAY_BIAS > closest ? 0.0 : 1.0;
        }
        float w = d0 * exp(-k * dy * t) * godrays_transmittance(dy, t);
        lit += w * vis;
        total += w;
    }

    // the step sum only estimates the share; the unshadowed integral is exact: 1 - e^{-tau}
    float share = total > 1e-12 ? lit / total : 1.0;
    float nearT = godrays_transmittance(dy, tMax);
    float s = share * (godrays_transmittance(dy, tStart) - nearT);
    // the visible share of the marched segment, not the whole ray: a tree's shadow is a few
    // metres of a kilometre of haze, and averaged over all of it no shaft would ever read
    frag_rays = vec4(s, share, dist, 1.0);
}
