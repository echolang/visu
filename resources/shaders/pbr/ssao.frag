#version 450

layout(location = 0) in vec2 v_uv;
layout(location = 0) out float frag_ao;

#include "visu/camera.glsl"
#include "visu/screen.glsl"

#define SSAO_MAX_SAMPLES 64

layout(std140, set = 0, binding = 0) uniform SsaoUniforms {
    // radius, bias, strength, sample count
    vec4 u_params;
    // target width, height, noise scale x, noise scale y
    vec4 u_screen;
    vec4 u_samples[SSAO_MAX_SAMPLES];
};

layout(set = 1, binding = 0) uniform sampler2D gbuffer_position;
layout(set = 1, binding = 1) uniform sampler2D gbuffer_normal;
layout(set = 1, binding = 2) uniform sampler2D noise_texture;

/*
 * Occlusion is measured against the world position attachment rather
 * than the depth buffer: the comparison then happens in view-space
 * units, which survive a change of depth range, and the pass needs no
 * depth texture binding at all.
 */
void main()
{
    vec4 P = texture(gbuffer_position, v_uv);

    if (P.a < 0.5) {
        frag_ao = 1.0;
        return;
    }

    vec3 view_pos = (u_view * vec4(P.xyz, 1.0)).xyz;
    vec3 view_normal = normalize(mat3(u_view) * texture(gbuffer_normal, v_uv).xyz);
    vec3 noise = normalize(texture(noise_texture, v_uv * u_screen.zw).xyz * 2.0 - 1.0);
    vec3 tangent = normalize(noise - view_normal * dot(noise, view_normal));
    vec3 bitangent = cross(view_normal, tangent);
    mat3 TBN = mat3(tangent, bitangent, view_normal);

    float radius = u_params.x;
    float bias = u_params.y;
    float strength = u_params.z;
    int count = int(u_params.w);
    float occlusion = 0.0;

    for (int i = 0; i < count; ++i)
    {
        vec3 sample_view = view_pos + TBN * u_samples[i].xyz * radius;
        vec4 clip = u_projection * vec4(sample_view, 1.0);

        if (clip.w <= 0.0) {
            continue;
        }

        vec4 occluder = texture(gbuffer_position, uv_from_ndc(clip.xy / clip.w));

        if (occluder.a < 0.5) {
            continue;
        }

        float occluder_z = (u_view * vec4(occluder.xyz, 1.0)).z;

        // view space looks down -Z, so a larger z sits nearer the camera
        if (occluder_z >= sample_view.z + bias) {
            occlusion += smoothstep(0.0, 1.0, radius / abs(view_pos.z - occluder_z));
        }
    }

    occlusion = 1.0 - (occlusion / float(count));
    frag_ao = pow(clamp(occlusion, 0.0, 1.0), strength);
}
