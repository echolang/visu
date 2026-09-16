/**
 * GBuffer writes. Four attachments, the cap visu's render passes
 * allow, so metallic and roughness ride in alpha channels:
 *
 *   0 rgba16f  xyz world position
 *   1 rgba16f  xyz world normal
 *   2 rgba8    rgb albedo, a metallic
 *   3 rgba16f  rgb emissive, a roughness
 */
#ifndef VISU_GBUFFER_LAYOUT_GLSL
#define VISU_GBUFFER_LAYOUT_GLSL

layout(location = 0) out vec4 gbuffer_out_position;
layout(location = 1) out vec4 gbuffer_out_normal;
layout(location = 2) out vec4 gbuffer_out_albedo;
layout(location = 3) out vec4 gbuffer_out_emissive;

void gbuffer_write(
    vec3 position,
    vec3 normal,
    vec3 albedo,
    float metallic,
    float roughness,
    vec3 emissive
)
{
    gbuffer_out_position = vec4(position, 1.0);
    gbuffer_out_normal = vec4(normal, 0.0);
    gbuffer_out_albedo = vec4(albedo, metallic);
    gbuffer_out_emissive = vec4(emissive, roughness);
}

#endif
