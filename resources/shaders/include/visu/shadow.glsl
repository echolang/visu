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

int csm_index_world(vec3 world, mat4 light_space[VISU_SHADOW_CASCADES])
{
    for (int i = 0; i < VISU_SHADOW_CASCADES; ++i) {
        vec4 clip = light_space[i] * vec4(world, 1.0);
        if (clip.w <= 0.0) {
            continue;
        }
        vec3 proj = clip.xyz / clip.w;
        vec2 uv = uv_from_ndc(proj.xy);
        if (proj.z < 0.0 || proj.z > 1.0) {
            continue;
        }
        if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
            continue;
        }
        return i;
    }
    return VISU_SHADOW_CASCADES - 1;
}

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

float shadow_gather(
    sampler2DArray shadowmap,
    vec3 world_position,
    vec3 normal,
    vec3 light_dir,
    mat4 light_space,
    int shadow_index,
    float min_bias
)
{
    vec4 clip = light_space * vec4(world_position, 1.0);
    if (clip.w <= 0.0) {
        return 0.0;
    }
    vec3 proj = clip.xyz / clip.w;
    vec2 uv = uv_from_ndc(proj.xy);
    float current_depth = proj.z;

    if (current_depth > 1.0) {
        return 0.0;
    }

    float bias = max(min_bias * (1.0 - dot(normal, light_dir)), min_bias);

    // a tap past this face is not a sample of it; dividing by nine would count it as lit
    float shadow = 0.0;
    int taps = 0;
    vec3 texel = 1.0 / vec3(textureSize(shadowmap, 0));
    for (int x = -1; x <= 1; ++x) {
        for (int y = -1; y <= 1; ++y) {
            vec2 sample_uv = uv + vec2(x, y) * texel.xy;
            if (sample_uv.x < 0.0 || sample_uv.x > 1.0 || sample_uv.y < 0.0 || sample_uv.y > 1.0) {
                continue;
            }
            float closest = texture(shadowmap, vec3(sample_uv, float(shadow_index))).r;
            shadow += current_depth - bias > closest ? 1.0 : 0.0;
            taps++;
        }
    }
    if (taps == 0) {
        return 0.0;
    }
    return clamp(shadow / float(taps), 0.0, 1.0);
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
    float biases[VISU_SHADOW_CASCADES] = float[](
        0.0012, 0.0017, 0.0018, 0.0005, 0.0012
    );
    return shadow_gather(
        shadowmap,
        world_position,
        normal,
        light_dir,
        light_space,
        shadow_index,
        biases[shadow_index]
    );
}

#endif
