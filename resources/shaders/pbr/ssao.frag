#version 450

layout(location = 0) in vec2 v_uv;
layout(location = 0) out float frag_ao;

#include "visu/camera.glsl"
#include "visu/screen.glsl"

#define SSAO_MAX_SAMPLES 64

layout(std140, set = 0, binding = 0) uniform SsaoUniforms {
    // radius, bias ratio, strength, sample count
    vec4 u_params;
    // target width, height, noise scale x, noise scale y
    vec4 u_screen;
    vec4 u_samples[SSAO_MAX_SAMPLES];
};

layout(set = 1, binding = 0) uniform sampler2D gbuffer_position;
layout(set = 1, binding = 1) uniform sampler2D gbuffer_normal;
layout(set = 1, binding = 2) uniform sampler2D noise_texture;
layout(set = 1, binding = 3) uniform sampler2D gbuffer_id;

#include "visu/gbuffer_id.glsl"

/*
 * The position attachment stores camera-relative xyz (P - eye). A view
 * matrix is [R | -R·eye], so mat3(u_view) * P_relative equals
 * (u_view * vec4(P_world, 1)).xyz. Measuring against that rather than
 * depth keeps the comparison in view-space units, survives a change of
 * depth range, and needs no depth texture binding.
 */
void main()
{
    vec4 P = texture(gbuffer_position, v_uv);

    if (P.a < 0.5) {
        frag_ao = 1.0;
        return;
    }

    float radius = u_params.x;
    // rgba16f camera-relative P has ulp |P|/1024. Four ulps covers both
    // ends of a sample plus the binade step that made the far squares.
    // Beyond that the kernel is smaller than the lattice, so fade out.
    float quant = length(P.xyz) * (1.0 / 256.0);
    float bias = max(u_params.y * radius, quant);
    float fade = 1.0 - smoothstep(0.4, 1.0, bias / max(radius, 1e-5));
    float strength = u_params.z;

    if (fade <= 0.0) {
        frag_ao = 1.0;
        return;
    }

    uint centre_id = gbuffer_id_decode(texture(gbuffer_id, v_uv).r);

    vec3 view_pos = mat3(u_view) * P.xyz;
    vec3 view_normal = normalize(mat3(u_view) * texture(gbuffer_normal, v_uv).xyz);
    vec3 noise = normalize(texture(noise_texture, v_uv * u_screen.zw).xyz * 2.0 - 1.0);
    vec3 tangent = normalize(noise - view_normal * dot(noise, view_normal));
    vec3 bitangent = cross(view_normal, tangent);
    mat3 TBN = mat3(tangent, bitangent, view_normal);

    int count = int(u_params.w);
    float occlusion = 0.0;

    for (int i = 0; i < count; ++i)
    {
        vec3 sample_view = view_pos + TBN * u_samples[i].xyz * radius;
        vec4 clip = u_projection * vec4(sample_view, 1.0);

        if (clip.w <= 0.0) {
            continue;
        }

        vec2 occluder_uv = uv_from_ndc(clip.xy / clip.w);
        vec4 occluder = texture(gbuffer_position, occluder_uv);

        if (occluder.a < 0.5) {
            continue;
        }

        float occluder_z = (mat3(u_view) * occluder.xyz).z;

        // view space looks down -Z, so a larger z sits nearer the camera
        if (occluder_z >= sample_view.z + bias) {
            uint oid = gbuffer_id_decode(texture(gbuffer_id, occluder_uv).r);
            float weight = 1.0;
            if (gbuffer_id_soft_ao(oid)) {
                weight = 0.15;
            }
            occlusion += weight * smoothstep(0.0, 1.0, radius / abs(view_pos.z - occluder_z));
        }
    }

    float ao = 1.0 - (occlusion / float(count));
    ao = mix(1.0, ao, fade);
    if (gbuffer_id_soft_ao(centre_id)) {
        ao = mix(1.0, ao, 0.35);
    }
    frag_ao = pow(clamp(ao, 0.0, 1.0), strength);
}
