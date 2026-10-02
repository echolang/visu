/**
 * The bank's material table the GPU-driven programs read by a meshlet's material index. Mirrors
 * visu::graphics::ModelMaterialGpu: the four vectors of ModelMaterialData, then each map's slot in
 * the bank's TextureTable (the white or flat fallback when the material has none; the flags in
 * factors.z still say which maps are real). Every model map samples with table sampler 0. The
 * includer includes visu/bindless.glsl and enables GL_EXT_nonuniform_qualifier.
 */
#ifndef VISU_MATERIAL_TABLE_GLSL
#define VISU_MATERIAL_TABLE_GLSL

struct ModelMaterial {
    // rgb albedo fallback, a alpha cutoff (0 = opaque)
    vec4 base_color;
    // roughness, metallic, map presence flags, parallax relief in tiles
    vec4 factors;
    // uv scale, parallax most steps, parallax fade in metres
    vec4 uv_scale;
    // rgb multiplies the emissive map; zero writes black and skips the sample
    vec4 emissive;
    // albedo, normal, roughness, metallic
    uvec4 maps0;
    // ao, alpha, emissive, height
    uvec4 maps1;
};

layout(std430, set = 2, binding = 8) readonly buffer MaterialTable {
    ModelMaterial materials[];
};

#define MODEL_MAP_ALBEDO 1
#define MODEL_MAP_NORMAL 2
#define MODEL_MAP_ROUGHNESS 4
#define MODEL_MAP_METALLIC 8
#define MODEL_MAP_AO 16
#define MODEL_MAP_ALPHA 32
#define MODEL_TABLE_SAMPLER 0u

// true where the material's cutoff drops the fragment at mesh uv `meshUv`
bool table_alpha_cutout(ModelMaterial mat, vec2 meshUv)
{
    vec2 uv = meshUv * mat.uv_scale.xy;
    int flags = int(mat.factors.z + 0.5);
    float alpha = 1.0;
    if ((flags & MODEL_MAP_ALBEDO) != 0) {
        alpha = table_sample(mat.maps0.x, MODEL_TABLE_SAMPLER, uv).a;
    }
    if ((flags & MODEL_MAP_ALPHA) != 0) {
        alpha = table_sample(mat.maps1.y, MODEL_TABLE_SAMPLER, uv).r;
    }
    return mat.base_color.a > 0.0 && alpha < mat.base_color.a;
}

#endif
