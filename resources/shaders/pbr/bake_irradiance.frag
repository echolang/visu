#version 450

layout(location = 0) in vec3 v_position;
layout(location = 0) out vec4 frag_color;

layout(set = 1, binding = 0) uniform samplerCube u_env_cubemap;

#include "visu/constants.glsl"

void main()
{
    vec3 N = normalize(v_position);
    vec3 irradiance = vec3(0.0);

    vec3 up = vec3(0.0, 1.0, 0.0);
    vec3 right = normalize(cross(up, N));
    up = normalize(cross(N, right));

    float sample_delta = 0.025;
    float samples = 0.0;

    for (float phi = 0.0; phi < 2.0 * PI; phi += sample_delta)
    {
        for (float theta = 0.0; theta < 0.5 * PI; theta += sample_delta)
        {
            vec3 tangent = vec3(sin(theta) * cos(phi), sin(theta) * sin(phi), cos(theta));
            vec3 dir = tangent.x * right + tangent.y * up + tangent.z * N;
            irradiance += textureLod(u_env_cubemap, dir, 0.0).rgb * cos(theta) * sin(theta);
            samples += 1.0;
        }
    }

    // the light pass divides by PI again; the pair cancels
    irradiance = PI * irradiance * (1.0 / samples);
    frag_color = vec4(irradiance, 1.0);
}
