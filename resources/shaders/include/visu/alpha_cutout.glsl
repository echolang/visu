/**
 * The alpha cutout the depth-only and mask passes share: visu::graphics::ModelMaterialData at
 * slot 0 and the material's albedo and alpha maps decide whether a fragment of a cut-out
 * material (foliage cards) is dropped.
 */
#ifndef VISU_ALPHA_CUTOUT_GLSL
#define VISU_ALPHA_CUTOUT_GLSL

// visu::graphics::ModelMaterialData, one upload per material batch
layout(std140, set = 0, binding = 0) uniform ModelMaterialData {
    // rgb albedo fallback, a alpha cutoff (0 = opaque)
    vec4 u_base_color;
    vec4 u_factors;
    vec4 u_uv_scale;
};

layout(set = 1, binding = 0) uniform sampler2D map_albedo;
layout(set = 1, binding = 5) uniform sampler2D map_alpha;

const int MAP_ALBEDO = 1;
const int MAP_ALPHA = 32;

// true where the material's cutoff drops the fragment at mesh uv `meshUv`
bool alpha_cutout(vec2 meshUv)
{
    vec2 uv = meshUv * u_uv_scale.xy;
    int flags = int(u_factors.z + 0.5);
    float alpha = 1.0;
    if ((flags & MAP_ALBEDO) != 0) {
        alpha = texture(map_albedo, uv).a;
    }
    if ((flags & MAP_ALPHA) != 0) {
        alpha = texture(map_alpha, uv).r;
    }
    return u_base_color.a > 0.0 && alpha < u_base_color.a;
}

#endif
