/**
 * Cascaded shadow sampling for the deferred light pass.
 * Splits are view-space Z (negative, more negative is farther).
 * Light projection is clipZeroOne: z is already 0..1. xy goes through
 * uv_from_ndc, because the map's v runs top-down while NDC +Y is up;
 * without that flip a receiver reads the map mirrored about the cascade
 * centre and the terrain shadows itself in straight-edged wedges.
 */
#ifndef VISU_SHADOW_GLSL
#define VISU_SHADOW_GLSL

#include "visu/screen.glsl"

#ifndef VISU_SHADOW_CASCADES
#define VISU_SHADOW_CASCADES 5
#endif

int csm_index(float depth, vec4 splits)
{
    int shadow_index = 0;
    if (depth < splits.x) {
        shadow_index = 1;
    }
    if (depth < splits.y) {
        shadow_index = 2;
    }
    if (depth < splits.z) {
        shadow_index = 3;
    }
    if (depth < splits.w) {
        shadow_index = 4;
    }
    return shadow_index;
}

float shadow_sample(
    sampler2DArray shadowmap,
    vec3 world_position,
    vec3 normal,
    vec3 light_dir,
    mat4 light_space,
    int shadow_index
)
{
    vec4 clip = light_space * vec4(world_position, 1.0);
    vec3 proj = clip.xyz / clip.w;
    vec2 uv = uv_from_ndc(proj.xy);
    float current_depth = proj.z;

    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0 || current_depth > 1.0) {
        return 0.0;
    }

    float biases[VISU_SHADOW_CASCADES] = float[](
        0.0012, 0.0017, 0.0018, 0.0005, 0.0012
    );
    float min_bias = biases[shadow_index];
    float bias = max(min_bias * (1.0 - dot(normal, light_dir)), min_bias);

    float shadow = 0.0;
    vec3 texel = 1.0 / vec3(textureSize(shadowmap, 0));
    for (int x = -1; x <= 1; ++x) {
        for (int y = -1; y <= 1; ++y) {
            vec2 sample_uv = uv + vec2(x, y) * texel.xy;
            if (sample_uv.x < 0.0 || sample_uv.x > 1.0 || sample_uv.y < 0.0 || sample_uv.y > 1.0) {
                continue;
            }
            float closest = texture(shadowmap, vec3(sample_uv, float(shadow_index))).r;
            shadow += current_depth - bias > closest ? 1.0 : 0.0;
        }
    }
    return clamp(shadow / 9.0, 0.0, 1.0);
}

#endif
