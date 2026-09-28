/**
 * Composite side of the light shafts: the resolved history at texture binding 15, a
 * depth-aware upsample to the pixel, and the Henyey-Greenstein phase. `fog.glsl` pulls this
 * in when the includer defines VISU_FOG_RAYS; programs that do not composite shafts never
 * declare the sampler.
 */
#ifndef VISU_GODRAYS_GLSL
#define VISU_GODRAYS_GLSL

#include "visu/godrays_common.glsl"

layout(set = 1, binding = 15) uniform sampler2D godrays_resolved;

/**
 * (S, visible share) at screen `uv` for a pixel `dist` metres out. Four texel taps, each
 * weighted bilinearly and by how close its distance is, so a shaft never bleeds across a
 * silhouette.
 */
vec2 godrays_fetch(vec2 uv, float dist)
{
    vec2 size = vec2(textureSize(godrays_resolved, 0));
    vec2 st = uv * size - 0.5;
    vec2 cell = floor(st);
    vec2 f = st - cell;
    ivec2 base = ivec2(cell);
    ivec2 top = ivec2(size) - ivec2(1);
    float d = min(dist, GODRAY_SKY_DEPTH);
    vec2 sum = vec2(0.0);
    float weight = 0.0;
    for (int j = 0; j < 2; ++j) {
        for (int i = 0; i < 2; ++i) {
            vec4 s = texelFetch(godrays_resolved, clamp(base + ivec2(i, j), ivec2(0), top), 0);
            float bx = i == 0 ? 1.0 - f.x : f.x;
            float by = j == 0 ? 1.0 - f.y : f.y;
            float rel = abs(s.b - d) / max(d, 1.0);
            float w = bx * by / (0.001 + rel) + 1e-6;
            sum += s.rg * w;
            weight += w;
        }
    }
    return sum / weight;
}

/**
 * Henyey-Greenstein phase for the angle between the view ray and the way to the light.
 */
float godrays_phase(float cosTheta, float g)
{
    float g2 = g * g;
    float denom = max(1.0 + g2 - 2.0 * g * cosTheta, 1e-4);
    return (1.0 - g2) / (12.566370614 * denom * sqrt(denom));
}

/**
 * Two lobes: a tight core around the light plus a wide lobe that carries the streaks away
 * from it. Added, not mixed, so a stronger wide lobe never thins the core's glow. `lobes` is
 * (core g, wide g, wide share).
 */
float godrays_phase2(float cosTheta, vec3 lobes)
{
    return godrays_phase(cosTheta, lobes.x) + godrays_phase(cosTheta, lobes.y) * lobes.z;
}

#endif
