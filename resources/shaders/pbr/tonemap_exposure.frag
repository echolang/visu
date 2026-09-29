#version 450

#pragma visu variant probe TONEMAP_PROBE=1

// The camera exposure for this frame, as one texel: r the EV the frame is shown at, g the
// target it adapts towards, b the illuminance it metered, a 1.
//
// The meter is the light falling on the ground, not the image: the sun, the moon and the
// night ambient come in from the CPU, the sky's share is the irradiance probe straight up.
// A grey card under that light is the key. The image only speaks through its highlights: when
// the brightest coarse cell would land more than `highlight` stops over the key, the EV comes
// down by a share of the excess. Then the EV walks from last frame's value towards the target.

layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 frag_exposure;

#include "visu/tonemap_uniforms.glsl"

layout(set = 1, binding = 0) uniform sampler2D u_stats;
layout(set = 1, binding = 1) uniform sampler2D u_previous;
#ifdef TONEMAP_PROBE
layout(set = 1, binding = 6) uniform samplerCube u_irradiance;
layout(set = 1, binding = 9) uniform samplerCube u_irradiance_b;
#endif

void main()
{
    float peak = -64.0;
    for (int y = 0; y < 4; ++y) {
        for (int x = 0; x < 8; ++x) {
            peak = max(peak, texelFetch(u_stats, ivec2(x, y), 0).g);
        }
    }

    float lux = u_tm_meter.z;
#ifdef TONEMAP_PROBE
    {
        vec3 up = mix(
            textureLod(u_irradiance, vec3(0.0, 1.0, 0.0), 0.0).rgb,
            textureLod(u_irradiance_b, vec3(0.0, 1.0, 0.0), 0.0).rgb,
            u_tm_meter.w
        );
        lux += dot(up, TONEMAP_LUMA);
    }
#endif

    // strength 1 puts a grey card at the key under any light; 0 is the fixed compensation
    float ev = u_tm_exposure.x + u_tm_adapt.x * (u_tm_adapt.w - log2(max(lux, 1e-5)));
    float over = peak + ev - (u_tm_local.x + u_tm_meter.x);
    if (over > 0.0) {
        ev -= over * u_tm_meter.y;
    }
    ev = clamp(ev, u_tm_adapt.y, u_tm_adapt.z);

    float shown = ev;
    if (u_tm_history.z > 0.5) {
        float last = texelFetch(u_previous, ivec2(0), 0).r;
        float blend = ev > last ? u_tm_history.x : u_tm_history.y;
        shown = mix(last, ev, blend);
    }
    frag_exposure = vec4(shown, ev, lux, 1.0);
}
