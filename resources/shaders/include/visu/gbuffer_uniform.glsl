/**
 * GBuffer reads for the deferred light pass. Slots match
 * visu::graphics::LightPass: 0 position, 1 normal, 2 albedo,
 * 3 emissive, 4 ambient occlusion.
 */
#ifndef VISU_GBUFFER_UNIFORM_GLSL
#define VISU_GBUFFER_UNIFORM_GLSL

layout(set = 1, binding = 0) uniform sampler2D gbuffer_position;
layout(set = 1, binding = 1) uniform sampler2D gbuffer_normal;
layout(set = 1, binding = 2) uniform sampler2D gbuffer_albedo;
layout(set = 1, binding = 3) uniform sampler2D gbuffer_emissive;
layout(set = 1, binding = 4) uniform sampler2D gbuffer_ao;

struct GBuffer
{
    vec3 P;
    vec3 N;
    vec3 albedo;
    float metallic;
    float roughness;
    float ao;
    vec3 emissive;
    // 0 where nothing was drawn, so the skybox can show through
    float coverage;
};

/**
 * Raw unpack; no normalising or clamping. `pbr_surface_make` does that.
 */
GBuffer gbuffer_make(vec2 uv)
{
    vec4 position = texture(gbuffer_position, uv);
    vec4 normal = texture(gbuffer_normal, uv);
    vec4 albedo = texture(gbuffer_albedo, uv);
    vec4 emissive = texture(gbuffer_emissive, uv);

    GBuffer gbuffer;
    gbuffer.P = position.rgb;
    gbuffer.N = normal.rgb;
    gbuffer.albedo = albedo.rgb;
    gbuffer.metallic = albedo.a;
    gbuffer.roughness = emissive.a;
    gbuffer.emissive = emissive.rgb;
    gbuffer.ao = texture(gbuffer_ao, uv).r;
    gbuffer.coverage = position.a;

    return gbuffer;
}

#endif
