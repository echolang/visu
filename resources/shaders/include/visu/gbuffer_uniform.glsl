/**
 * GBuffer reads for the deferred light pass.
 * 0 position (camera-relative xyz in the attachment; gbuffer.P is world),
 * 1 normal, 2 albedo, 3 material (roughness, metallic, AO),
 * 4 emissive, 5 id (GBufferId / 255), 6+ environment / IBL, 11 shadow,
 * 12 screen-space AO.
 */
#ifndef VISU_GBUFFER_UNIFORM_GLSL
#define VISU_GBUFFER_UNIFORM_GLSL

#include "visu/camera.glsl"
#include "visu/gbuffer_id.glsl"

layout(set = 1, binding = 0) uniform sampler2D gbuffer_position;
layout(set = 1, binding = 1) uniform sampler2D gbuffer_normal;
layout(set = 1, binding = 2) uniform sampler2D gbuffer_albedo;
layout(set = 1, binding = 3) uniform sampler2D gbuffer_material;
layout(set = 1, binding = 4) uniform sampler2D gbuffer_emissive;
layout(set = 1, binding = 5) uniform sampler2D gbuffer_id;
layout(set = 1, binding = 12) uniform sampler2D gbuffer_ao;

struct GBuffer
{
    vec3 P;
    vec3 relative;
    vec3 N;
    vec3 albedo;
    float metallic;
    float roughness;
    float ao;
    vec3 emissive;
    uint id;
    float coverage;
};

GBuffer gbuffer_make(vec2 uv)
{
    vec4 position = texture(gbuffer_position, uv);
    vec4 normal = texture(gbuffer_normal, uv);
    vec4 albedo = texture(gbuffer_albedo, uv);
    vec4 material = texture(gbuffer_material, uv);

    GBuffer gbuffer;
    gbuffer.relative = position.rgb;
    gbuffer.P = position.rgb + u_camera_position.xyz;
    gbuffer.N = normal.rgb;
    gbuffer.albedo = albedo.rgb;
    gbuffer.roughness = material.r;
    gbuffer.metallic = material.g;
    gbuffer.ao = material.b * texture(gbuffer_ao, uv).r;
    gbuffer.emissive = texture(gbuffer_emissive, uv).rgb;
    gbuffer.id = gbuffer_id_decode(texture(gbuffer_id, uv).r);
    gbuffer.coverage = position.a;
    return gbuffer;
}

#endif

