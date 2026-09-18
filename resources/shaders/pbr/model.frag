#version 450

layout(location = 0) in vec3 v_position;
layout(location = 1) in vec3 v_normal;
layout(location = 2) in vec4 v_tangent;
layout(location = 3) in vec2 v_uv;
layout(location = 4) in vec4 v_tint;

// visu::graphics::ModelMaterialData, one upload per material batch
layout(std140, set = 0, binding = 0) uniform ModelMaterialData {
    // rgb albedo fallback, a alpha cutoff (0 = opaque)
    vec4 u_base_color;
    // roughness, metallic, map presence flags, unused
    vec4 u_factors;
    vec4 u_uv_scale;
};

layout(set = 1, binding = 0) uniform sampler2D map_albedo;
layout(set = 1, binding = 1) uniform sampler2D map_normal;
layout(set = 1, binding = 2) uniform sampler2D map_roughness;
layout(set = 1, binding = 3) uniform sampler2D map_metallic;
layout(set = 1, binding = 4) uniform sampler2D map_ao;
layout(set = 1, binding = 5) uniform sampler2D map_alpha;

#include "visu/gbuffer_layout.glsl"

const int MAP_ALBEDO = 1;
const int MAP_NORMAL = 2;
const int MAP_ROUGHNESS = 4;
const int MAP_METALLIC = 8;
const int MAP_AO = 16;
const int MAP_ALPHA = 32;

void main()
{
    vec2 uv = v_uv * u_uv_scale.xy;
    int flags = int(u_factors.z + 0.5);

    vec3 albedo = u_base_color.rgb;
    float alpha = 1.0;
    if ((flags & MAP_ALBEDO) != 0) {
        vec4 sampled = texture(map_albedo, uv);
        albedo = sampled.rgb;
        alpha = sampled.a;
    }

    if ((flags & MAP_ALPHA) != 0) {
        alpha = texture(map_alpha, uv).r;
    }

    // cut-out: the cutoff is the material's, 0 disables the test
    if (u_base_color.a > 0.0 && alpha < u_base_color.a) {
        discard;
    }

    albedo *= v_tint.rgb;

    vec3 n = normalize(v_normal);
    if (!gl_FrontFacing) {
        n = -n;
    }

    if ((flags & MAP_NORMAL) != 0) {
        vec3 t = normalize(v_tangent.xyz);
        t = normalize(t - n * dot(n, t));
        vec3 b = cross(n, t) * v_tangent.w;
        vec3 tn = texture(map_normal, uv).rgb * 2.0 - 1.0;
        n = normalize(mat3(t, b, n) * tn);
    }

    float roughness = u_factors.x;
    if ((flags & MAP_ROUGHNESS) != 0) {
        roughness = texture(map_roughness, uv).r;
    }

    float metallic = u_factors.y;
    if ((flags & MAP_METALLIC) != 0) {
        metallic = texture(map_metallic, uv).r;
    }

    float ao = 1.0;
    if ((flags & MAP_AO) != 0) {
        ao = texture(map_ao, uv).r;
    }

    gbuffer_write(v_position, n, albedo, metallic, roughness, vec3(0.0), ao);
}
