#version 450

layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 frag_color;

#include "visu/constants.glsl"
#include "visu/functions/importance_sampling.glsl"

// IBL uses a different k than direct lighting
float geometry_schlick_ggx_ibl(float NdotV, float roughness)
{
    float a = roughness;
    float k = (a * a) / 2.0;
    return NdotV / (NdotV * (1.0 - k) + k);
}

float geometry_smith_ibl(vec3 N, vec3 V, vec3 L, float roughness)
{
    float NdotV = max(dot(N, V), 0.0);
    float NdotL = max(dot(N, L), 0.0);
    return geometry_schlick_ggx_ibl(NdotL, roughness) * geometry_schlick_ggx_ibl(NdotV, roughness);
}

vec2 integrate_brdf(float NdotV, float roughness)
{
    vec3 V = vec3(sqrt(1.0 - NdotV * NdotV), 0.0, NdotV);
    vec3 N = vec3(0.0, 0.0, 1.0);

    float A = 0.0;
    float B = 0.0;

    const uint sample_count = 256u;

    for (uint i = 0u; i < sample_count; ++i)
    {
        vec2 Xi = hammersley(i, sample_count);
        vec3 H = importance_sample_ggx(Xi, N, roughness);
        vec3 L = normalize(2.0 * dot(V, H) * H - V);

        float NdotL = max(L.z, 0.0);
        float NdotH = max(H.z, 0.0);
        float VdotH = max(dot(V, H), 0.0);

        if (NdotL > 0.0)
        {
            float G = geometry_smith_ibl(N, V, L, roughness);
            float G_Vis = (G * VdotH) / (NdotH * NdotV);
            float Fc = pow(1.0 - VdotH, 5.0);

            A += (1.0 - Fc) * G_Vis;
            B += Fc * G_Vis;
        }
    }

    return vec2(A, B) / float(sample_count);
}

void main()
{
    vec2 lut = integrate_brdf(v_uv.x, v_uv.y);
    frag_color = vec4(lut, 0.0, 1.0);
}
