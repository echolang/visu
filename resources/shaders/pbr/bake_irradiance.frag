#version 450

layout(location = 0) in vec3 v_position;
layout(location = 0) out vec4 frag_color;

layout(set = 1, binding = 0) uniform samplerCube u_env_cubemap;

#include "visu/capture.glsl"
#include "visu/constants.glsl"
#include "visu/functions/importance_sampling.glsl"

void main()
{
    vec3 N = normalize(v_position);
    vec3 irradiance = vec3(0.0);

    vec3 up = vec3(0.0, 1.0, 0.0);
    vec3 right = normalize(cross(up, N));
    up = normalize(cross(N, right));

    uint sample_count = uint(max(u_capture_params.z, 64.0));

    for (uint i = 0u; i < sample_count; ++i)
    {
        vec2 Xi = hammersley(i, sample_count);
        float phi = 2.0 * PI * Xi.x;
        float cos_theta = sqrt(1.0 - Xi.y);
        float sin_theta = sqrt(Xi.y);
        vec3 tangent = vec3(sin_theta * cos(phi), sin_theta * sin(phi), cos_theta);
        vec3 dir = tangent.x * right + tangent.y * up + tangent.z * N;
        irradiance += min(textureLod(u_env_cubemap, dir, 0.0).rgb, vec3(8.0));
    }

    // cosine-weighted hemisphere: pdf = cos/PI, estimator is Li * PI / N
    // the light pass divides by PI again; the pair cancels
    irradiance = PI * irradiance / float(sample_count);
    frag_color = vec4(irradiance, 1.0);
}
