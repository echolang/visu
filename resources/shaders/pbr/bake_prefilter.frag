#version 450

layout(location = 0) in vec3 v_position;
layout(location = 0) out vec4 frag_color;

layout(set = 1, binding = 0) uniform samplerCube u_env_cubemap;

#include "visu/capture.glsl"
#include "visu/constants.glsl"
#include "visu/functions/brdf.glsl"
#include "visu/functions/importance_sampling.glsl"

void main()
{
    vec3 N = normalize(v_position);
    vec3 V = N;

    float roughness = u_capture_params.x;
    float rough = max(roughness, 1e-4);
    float source_resolution = u_capture_params.y;

    const uint SAMPLE_COUNT = 4096u;
    vec3 prefiltered = vec3(0.0);
    float weight = 0.0;

    for (uint i = 0u; i < SAMPLE_COUNT; ++i)
    {
        vec2 Xi = hammersley(i, SAMPLE_COUNT);
        vec3 H = importance_sample_ggx(Xi, N, rough);
        vec3 L = normalize(2.0 * dot(V, H) * H - V);

        float NdotL = max(dot(N, L), 0.0);

        if (NdotL > 0.0)
        {
            float NdotH = max(dot(N, H), 0.0);
            float D = distribution_GGX(NdotH, rough);
            float HdotV = max(dot(H, V), 0.0);
            float pdf = D * NdotH / max(4.0 * HdotV, 1e-6) + 1e-4;

            float sa_texel = 4.0 * PI / (6.0 * source_resolution * source_resolution);
            float sa_sample = 1.0 / (float(SAMPLE_COUNT) * pdf + 1e-4);

            float mip = 0.0;

            if (roughness >= 1e-4) {
                mip = 0.5 * log2(sa_sample / sa_texel);
            }

            prefiltered += textureLod(u_env_cubemap, L, mip).rgb * NdotL;
            weight += NdotL;
        }
    }

    prefiltered /= max(weight, 1e-6);
    frag_color = vec4(prefiltered, 1.0);
}
