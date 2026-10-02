#version 450
#extension GL_EXT_nonuniform_qualifier : require

// a material with a height map and relief marches it: parallax occlusion on every map sample
#pragma visu variant parallax MODEL_PARALLAX=1
#pragma visu variant skinned_parallax SKINNED=1 MODEL_PARALLAX=1
// the cut-out classes' depth pre-pass: the same vertex program, only the cutout here, so the
// shading pass after it (depth equal, no write) shades each pixel once however deep the foliage
#pragma visu variant prepass PREPASS=1
#pragma visu variant skinned_prepass SKINNED=1 PREPASS=1

// pbr/model.frag for the GPU-driven G-buffer draw: the material is the table row the meshlet
// names, its maps are TextureTable slots, so one draw covers every material of a class
layout(location = 0) in vec3 v_position;
layout(location = 1) in vec3 v_normal;
layout(location = 2) in vec4 v_tangent;
layout(location = 3) in vec2 v_uv;
layout(location = 4) in vec4 v_tint;
layout(location = 5) flat in uint v_material;

#include "visu/bindless.glsl"
#include "visu/material_table.glsl"
#include "visu/gbuffer_layout.glsl"

#ifdef MODEL_PARALLAX
#include "visu/camera.glsl"

uint g_height;

#include "visu/parallax.glsl"

float parallax_height(vec2 uv, vec2 dx, vec2 dy)
{
    return table_sample_grad(g_height, MODEL_TABLE_SAMPLER, uv, dx, dy).r;
}
#endif

#ifdef PREPASS
void main()
{
    if (table_alpha_cutout(materials[v_material], v_uv)) {
        discard;
    }
}
#else
void main()
{
    ModelMaterial mat = materials[v_material];
    vec2 uv = v_uv * mat.uv_scale.xy;
    int flags = int(mat.factors.z + 0.5);

    vec3 n = normalize(v_normal);
    if (!gl_FrontFacing) {
        n = -n;
    }

    vec3 t = normalize(v_tangent.xyz);
    t = normalize(t - n * dot(n, t));
    vec3 b = cross(n, t) * v_tangent.w;

#ifdef MODEL_PARALLAX
    g_height = mat.maps1.w;
    vec3 to_eye = u_camera_position.xyz - v_position;
    float depth = mat.factors.w * parallax_fade(length(to_eye), mat.uv_scale.w);
    if (depth > 1e-5) {
        vec2 dx = dFdx(uv);
        vec2 dy = dFdy(uv);
        uv = parallax_offset(uv, parallax_view(t, b, n, normalize(to_eye)), depth, mat.uv_scale.z, dx, dy);
    }
#endif

    vec3 albedo = mat.base_color.rgb;
    float alpha = 1.0;
    if ((flags & MODEL_MAP_ALBEDO) != 0) {
        vec4 sampled = table_sample(mat.maps0.x, MODEL_TABLE_SAMPLER, uv);
        albedo = sampled.rgb;
        alpha = sampled.a;
    }

    if ((flags & MODEL_MAP_ALPHA) != 0) {
        alpha = table_sample(mat.maps1.y, MODEL_TABLE_SAMPLER, uv).r;
    }

    // cut-out: the cutoff is the material's, 0 disables the test
    if (mat.base_color.a > 0.0 && alpha < mat.base_color.a) {
        discard;
    }

    albedo *= v_tint.rgb;

    if ((flags & MODEL_MAP_NORMAL) != 0) {
        vec3 tn = table_sample(mat.maps0.y, MODEL_TABLE_SAMPLER, uv).rgb * 2.0 - 1.0;
        n = normalize(mat3(t, b, n) * tn);
    }

    float roughness = mat.factors.x;
    if ((flags & MODEL_MAP_ROUGHNESS) != 0) {
        roughness = table_sample(mat.maps0.z, MODEL_TABLE_SAMPLER, uv).r;
    }

    float metallic = mat.factors.y;
    if ((flags & MODEL_MAP_METALLIC) != 0) {
        metallic = table_sample(mat.maps0.w, MODEL_TABLE_SAMPLER, uv).r;
    }

    float ao = 1.0;
    if ((flags & MODEL_MAP_AO) != 0) {
        ao = table_sample(mat.maps1.x, MODEL_TABLE_SAMPLER, uv).r;
    }

    vec3 emissive = vec3(0.0);
    if (dot(mat.emissive.rgb, vec3(1.0)) > 0.0) {
        emissive = mat.emissive.rgb * table_sample(mat.maps1.z, MODEL_TABLE_SAMPLER, uv).rgb;
    }

    gbuffer_write(v_position, n, albedo, metallic, roughness, emissive, ao);
}
#endif
