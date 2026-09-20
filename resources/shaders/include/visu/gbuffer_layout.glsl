/**
 * GBuffer writes. Six colour attachments:
 *
 *   0 rgba16f  xyz camera-relative position, a coverage
 *   1 rgba16f  xyz world normal
 *   2 rgba8    rgb albedo
 *   3 rgba8    r roughness, g metallic, b AO
 *   4 rgba16f  rgb emissive
 *   5 r8       GBufferId code / 255
 *
 * Callers pass world position; this subtracts the camera so fp16 error
 * tracks distance from the eye instead of world origin. The 7-argument
 * write is opaque models.
 */
#ifndef VISU_GBUFFER_LAYOUT_GLSL
#define VISU_GBUFFER_LAYOUT_GLSL

#include "visu/camera.glsl"
#include "visu/gbuffer_id.glsl"

layout(location = 0) out vec4 gbuffer_out_position;
layout(location = 1) out vec4 gbuffer_out_normal;
layout(location = 2) out vec4 gbuffer_out_albedo;
layout(location = 3) out vec4 gbuffer_out_material;
layout(location = 4) out vec4 gbuffer_out_emissive;
layout(location = 5) out vec4 gbuffer_out_id;

void gbuffer_write(
    vec3 position,
    vec3 normal,
    vec3 albedo,
    float metallic,
    float roughness,
    vec3 emissive,
    float ao,
    uint id
)
{
    gbuffer_out_position = vec4(position - u_camera_position.xyz, 1.0);
    gbuffer_out_normal = vec4(normal, 0.0);
    gbuffer_out_albedo = vec4(albedo, 1.0);
    gbuffer_out_material = vec4(roughness, metallic, clamp(ao, 0.0, 1.0), 1.0);
    gbuffer_out_emissive = vec4(emissive, 1.0);
    gbuffer_out_id = vec4(gbuffer_id_encode(id), 0.0, 0.0, 1.0);
}

void gbuffer_write(
    vec3 position,
    vec3 normal,
    vec3 albedo,
    float metallic,
    float roughness,
    vec3 emissive,
    float ao
)
{
    gbuffer_write(position, normal, albedo, metallic, roughness, emissive, ao, GBUFFER_ID_OPAQUE);
}

#endif
