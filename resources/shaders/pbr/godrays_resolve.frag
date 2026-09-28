#version 450

// Temporal resolve for the light shafts. Reprojects this texel's point into last frame's
// history, rejects it on a distance mismatch, clamps it to the raw 3x3 neighbourhood and
// blends. Writes (S, visible share, distance, 1) like the march.

layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 frag_rays;

#include "visu/godrays_uniforms.glsl"

layout(set = 1, binding = 0) uniform sampler2D u_raw;
layout(set = 1, binding = 1) uniform sampler2D u_previous;

void main()
{
    ivec2 size = ivec2(u_gr_target.xy + 0.5);
    ivec2 px = clamp(ivec2(gl_FragCoord.xy), ivec2(0), size - ivec2(1));
    vec4 raw = texelFetch(u_raw, px, 0);
    vec2 lo = raw.rg;
    vec2 hi = raw.rg;
    for (int y = -1; y <= 1; ++y) {
        for (int x = -1; x <= 1; ++x) {
            vec2 n = texelFetch(u_raw, clamp(px + ivec2(x, y), ivec2(0), size - ivec2(1)), 0).rg;
            lo = min(lo, n);
            hi = max(hi, n);
        }
    }

    vec2 rays = raw.rg;
    // a branch, not a weight: an unfilled history holds garbage that a zero weight keeps as NaN
    if (u_gr_medium.z > 0.5) {
        vec3 p = u_camera_position.xyz + godrays_view_dir(v_uv) * raw.b;
        vec4 clip = u_gr_prev_projection_view * vec4(p, 1.0);
        if (clip.w > 1e-4) {
            vec2 uv = uv_from_ndc(clip.xy / clip.w);
            if (uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0) {
                vec4 history = texture(u_previous, uv);
                float expect = length(p - u_gr_prev_camera.xyz);
                if (abs(history.b - expect) <= u_gr_medium.w * max(expect, 1.0)) {
                    rays = mix(raw.rg, clamp(history.rg, lo, hi), u_gr_medium.y);
                }
            }
        }
    }

    frag_rays = vec4(rays, raw.b, 1.0);
}
