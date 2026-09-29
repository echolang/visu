#version 450

layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 o_color;

layout(set = 1, binding = 0) uniform sampler2D u_mask;

#include "visu/outline_uniforms.glsl"

const float OUTLINE_STYLES = 4.0;
const int RING_TAPS = 8;

void main()
{
    vec4 here = texture(u_mask, v_uv);
    // the glow sits outside the silhouette; the object itself stays as lit unless its style
    // fills it (a placement ghost, which is only ever in the mask)
    if (here.r > 0.5) {
        int inside = int(clamp(floor(here.b * OUTLINE_STYLES), 0.0, OUTLINE_STYLES - 1.0));
        vec4 paint = u_params[inside];
        if (paint.z <= 0.0) {
            discard;
        }

        vec4 tint = u_colors[inside];
        o_color = vec4(tint.rgb, tint.a * paint.z * mix(paint.y, 1.0, here.g));
        return;
    }

    float widest = u_texel.z;
    float radii[3] = float[3](1.5, widest * 0.55, widest);
    float best = 0.0;
    int bestStyle = 0;
    int covered = 0;
    for (int ring = 0; ring < 3; ring++) {
        float radius = radii[ring];
        // stagger each ring so the taps do not line up into spokes
        float turn = float(ring) * 0.3927;
        for (int k = 0; k < RING_TAPS; k++) {
            float a = turn + float(k) * 0.7854;
            vec2 offset = vec2(cos(a), sin(a)) * radius * u_texel.xy;
            vec4 m = texture(u_mask, v_uv + offset);
            if (m.r < 0.5) {
                continue;
            }

            if (ring == 2) {
                covered++;
            }

            int style = int(clamp(floor(m.b * OUTLINE_STYLES), 0.0, OUTLINE_STYLES - 1.0));
            vec4 params = u_params[style];
            float reach = clamp(1.0 - radius / (params.x + 1.0), 0.0, 1.0);
            float strength = mix(params.y, 1.0, m.g) * reach;
            if (strength > best) {
                best = strength;
                bestStyle = style;
            }
        }
    }

    // a gap between leaves is ringed by the object on most sides; only the silhouette glows
    if (best <= 0.001 || covered > RING_TAPS - 3) {
        discard;
    }

    // ease out so the band reads as a glow, bright at the edge and soft at its reach
    best = sqrt(best);

    vec4 color = u_colors[bestStyle];
    o_color = vec4(color.rgb, color.a * best);
}
