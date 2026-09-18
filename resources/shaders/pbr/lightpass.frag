#version 450

#pragma visu variant ibl USE_IBL=1
#pragma visu variant env_cubemap USE_ENV_CUBEMAP=1

layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 fragment_color;

#include "visu/camera.glsl"
#include "visu/constants.glsl"
#include "visu/functions/gamma_corr.glsl"
#include "visu/functions/tone_mapping.glsl"
#include "visu/functions/brdf.glsl"
#include "visu/gbuffer_uniform.glsl"
#include "visu/pbr/surface.glsl"
#include "visu/pbr/shade.glsl"

// the light pass has no per-draw payload at slot 0 and slot 2 is LightUniforms
#define VISU_SKY_SLOT 0
#include "visu/fog.glsl"

layout(std140, set = 0, binding = 2) uniform LightUniforms {
    // xyz direction the sun travels, w intensity
    vec4 u_sun_direction;
    vec4 u_sun_color;
    // x prefiltered mip count, y environment mip count, z blend towards the second IBL state
    vec4 u_ibl;
};

#ifdef USE_ENV_CUBEMAP
layout(set = 1, binding = 6) uniform samplerCube environment_cubemap;
#endif

#ifdef USE_IBL
layout(set = 1, binding = 6) uniform samplerCube ibl_irradiance_map;
layout(set = 1, binding = 7) uniform samplerCube ibl_prefilter_map;
layout(set = 1, binding = 8) uniform sampler2D ibl_brdf_lut;
layout(set = 1, binding = 9) uniform samplerCube ibl_irradiance_map_b;
layout(set = 1, binding = 10) uniform samplerCube ibl_prefilter_map_b;
#endif

void main()
{
    GBuffer gbuffer = gbuffer_make(v_uv);

    // nothing was drawn here; leave the target for the skybox
    if (gbuffer.coverage < 0.5) {
        discard;
    }

    PBRSurface s = pbr_surface_make(gbuffer, u_camera_position.xyz);
    vec3 Lo = vec3(0.0);

    {
        vec3 L = normalize(-u_sun_direction.xyz);
        vec3 radiance = u_sun_color.rgb * u_sun_direction.w;
        Lo += pbr_shade(s, L, radiance);
    }

    vec3 ambient = vec3(0.0);
    {
        float NdotV = max(dot(s.N, s.V), 0.0);
        vec3 R = normalize(reflect(-s.V, s.N));

        vec3 F = fresnel_schlick_roughness(s.F0, NdotV, s.roughness);
        vec3 kS = F;
        vec3 kD = (vec3(1.0) - kS) * (1.0 - s.metallic);

        vec3 diffuseIBL = vec3(0.0);
#ifdef USE_IBL
        // lod 0: screen-space derivatives of N across a sphere are
        // meaningless, and a 1-mip cube reads black on iOS at high lod
        vec3 irradiance = mix(
            textureLod(ibl_irradiance_map, s.N, 0.0).rgb,
            textureLod(ibl_irradiance_map_b, s.N, 0.0).rgb,
            u_ibl.z
        );
        diffuseIBL = irradiance * s.albedo / PI;
#else
        diffuseIBL = vec3(0.03) * s.albedo;
#endif

        vec3 specIBL = vec3(0.0);
#ifdef USE_IBL
        float maxLod = max(u_ibl.x - 1.0, 0.0);
        vec3 prefiltered = mix(
            textureLod(ibl_prefilter_map, R, s.roughness * maxLod).rgb,
            textureLod(ibl_prefilter_map_b, R, s.roughness * maxLod).rgb,
            u_ibl.z
        );
        vec2 brdf = texture(ibl_brdf_lut, vec2(NdotV, s.roughness)).rg;
        specIBL = prefiltered * (s.F0 * brdf.x + brdf.y);
#elif defined(USE_ENV_CUBEMAP)
        // y is the env cube mip count; skip the 1x1 lod
        float maxLod = max(u_ibl.y - 2.0, 0.0);
        vec3 env = textureLod(environment_cubemap, R, s.roughness * maxLod).rgb;
        // no split-sum LUT on this path, so Fresnel alone
        specIBL = env * F;
#endif

        ambient = kD * diffuseIBL * s.ao + specIBL * s.ao;
    }

    vec3 color = Lo + ambient + s.emissive;
    color = fog_apply(color, gbuffer.relative);
    color = apply_tonemap(color);
    color = gamma_correct(color);
    fragment_color = vec4(color, 1.0);
}
