#version 450

#pragma visu variant ibl USE_IBL=1
#pragma visu variant env_cubemap USE_ENV_CUBEMAP=1
// a frame whose light table holds a lit spot: the cone costs the whole pass registers, so a
// frame of lights that shine every way runs without it
#pragma visu variant spot VISU_SPOTS=1
#pragma visu variant ibl_spot USE_IBL=1 VISU_SPOTS=1
#pragma visu variant env_cubemap_spot USE_ENV_CUBEMAP=1 VISU_SPOTS=1

layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 fragment_color;

#include "visu/camera.glsl"
#include "visu/constants.glsl"
#include "visu/functions/gamma_corr.glsl"
#include "visu/functions/brdf.glsl"
#include "visu/gbuffer_uniform.glsl"
#include "visu/pbr/surface.glsl"
#include "visu/pbr/shade.glsl"
#include "visu/shadow.glsl"

#define VISU_AERIAL_SLOT 14
#define VISU_FOG_RAYS
#include "visu/fog.glsl"
#include "visu/light_gpu.glsl"

layout(std140, set = 0, binding = 2) uniform LightUniforms {
    // xyz direction the sun travels, w intensity
    vec4 u_sun_direction;
    vec4 u_sun_color;
    // x prefiltered mip count, y environment mip count, z blend towards the second IBL state
    vec4 u_ibl;
    mat4 u_light_space[5];
    vec4 u_splits;
    // x fifth split, y enabled, z cascade tint, w 1 picks the cascade from world position
    vec4 u_shadow;
    // xyz direction the moon's light travels, w intensity
    vec4 u_moon_direction;
    // rgb moon colour, w 1 when the moon owns the shadow cascades
    vec4 u_moon_color;
    // rgb night sky ambient from above, w ground bounce share
    vec4 u_night_ambient;
    // x visible lights, y tile pixels, z tiles across, w mask words
    vec4 u_cluster_head;
    // x near, y slices per log2 metre, z slices, w seconds for the flicker
    vec4 u_cluster_z;
    // x 1 when the shadow atlas is bound, y its mip bias, z 1 paints the debug view, w the
    // shadow distance
    vec4 u_vsm;
};

#include "visu/lights.glsl"
#include "visu/vsm_sample.glsl"

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

layout(set = 1, binding = 11) uniform sampler2DArray shadowmap;

int csm_pick(vec3 world)
{
    if (u_shadow.w > 0.5) {
        return csm_index_world(world, u_light_space);
    }
    float view_z = (u_view * vec4(world, 1.0)).z;
    return csm_index(view_z, u_splits);
}

void main()
{
    // nothing was drawn here; leave the target for the skybox. The position texel carries the
    // coverage, so a sky pixel leaves before the other six attachments are read
    vec4 position = gbuffer_position_at(v_uv);
    if (position.a < 0.5) {
        discard;
    }

    GBuffer gbuffer = gbuffer_make(v_uv, position);

    PBRSurface s = pbr_surface_make(gbuffer, u_camera_position.xyz);
    vec3 Lo = vec3(0.0);
    vec3 transmitted = vec3(0.0);

    if (gbuffer.id == GBUFFER_ID_UNLIT) {
        fragment_color = vec4(fog_apply_rays(s.emissive, gbuffer.relative, v_uv), 1.0);
        return;
    }

    // the cascades belong to whichever of sun and moon is brighter; the other goes unshadowed
    bool moonKey = u_moon_color.w > 0.5;
    float keyVis = 1.0;
    if (u_shadow.y > 0.5) {
        int cascade = csm_pick(s.P);
        vec3 keyDir = moonKey ? u_moon_direction.xyz : u_sun_direction.xyz;
        keyVis = 1.0 - shadow_sample(
            shadowmap,
            s.P,
            s.N,
            normalize(keyDir),
            u_light_space[cascade],
            cascade
        );
    }

    if (u_sun_direction.w > 0.0) {
        vec3 L = normalize(-u_sun_direction.xyz);
        vec3 radiance = u_sun_color.rgb * u_sun_direction.w;
        float vis = moonKey ? 1.0 : keyVis;
        float wrap = gbuffer_id_wrap(gbuffer.id);
        Lo += pbr_shade_wrapped(s, L, radiance, wrap) * vis;
        float thickness = gbuffer_id_thickness(gbuffer.id);
        if (thickness > 0.0) {
            float t = pow(clamp(dot(s.V, -L), 0.0, 1.0), 2.0);
            transmitted = s.albedo * radiance * t * thickness * vis;
        }
    }

    // zero while the moon is down or new: the same for every pixel
    if (u_moon_direction.w > 0.0) {
        vec3 L = normalize(-u_moon_direction.xyz);
        vec3 radiance = u_moon_color.rgb * u_moon_direction.w;
        float vis = moonKey ? keyVis : 1.0;
        float wrap = gbuffer_id_wrap(gbuffer.id);
        Lo += pbr_shade_wrapped(s, L, radiance, wrap) * vis;
        float thickness = gbuffer_id_thickness(gbuffer.id);
        if (thickness > 0.0) {
            float t = pow(clamp(dot(s.V, -L), 0.0, 1.0), 2.0);
            transmitted += s.albedo * radiance * t * thickness * vis;
        }
    }

    vec3 vsmDebug = vec3(0.0);
    // the pixel's z-bin gives a range of visible lights, its tile a mask over them
    {
        float viewDepth = -(u_view * vec4(s.P, 1.0)).z;
        uvec2 range = light_range(viewDepth, u_cluster_head, u_cluster_z);
        if (range.x <= range.y) {
            vec2 pixel = min(v_uv * u_resolution.xy, u_resolution.xy - vec2(1.0));
            uint base = light_tile_base(pixel, u_cluster_head);
            // the world size of one screen pixel here, which picks the shadow page level
            float footprint = vsm_footprint(viewDepth, u_projection[1][1], u_resolution.y);
            float wrap = gbuffer_id_wrap(gbuffer.id);
            float thickness = gbuffer_id_thickness(gbuffer.id);
            for (uint w = range.x >> 5u; w <= (range.y >> 5u); w++) {
                uint bits = light_word(base, w, range);
                while (bits != 0u) {
                    uint b = uint(findLSB(bits));
                    bits &= bits - 1u;
                    uint slot = light_slot(w * 32u + b);
                    LightGpu l = u_lights[slot];
                    vec4 pr = l.position_radius;
                    vec3 toLight = pr.xyz - s.P;
                    float dist = length(toLight);
                    if (dist >= pr.w) {
                        continue;
                    }
                    vec3 Lc = toLight / max(dist, 1e-4);
                    vec3 radiance = light_radiance(l, dist, u_cluster_z.w);
#ifdef VISU_SPOTS
                    // outside a spot's cone: no light, so no shadow lookup either
                    float cone = light_cone(l, -Lc);
                    if (cone <= 0.0) {
                        continue;
                    }
                    radiance *= cone;
#endif
                    vec3 Ls = pbr_sphere_l(toLight, s.V, s.N, l.source.x);
                    float vis = 1.0;
                    float fade = vsm_light_fade(l, u_camera_position.xyz, u_vsm);
                    if (fade > 0.0) {
                        float seen = vsm_lookup(slot, pr.xyz, pr.w, s.P + s.N * l.source.z, footprint, u_vsm.y);
                        vis = mix(1.0, seen < -0.5 ? 1.0 : seen, fade);
                        // debug view: red has no page, magenta a stale one, green is lit, blue is shadowed
                        if (u_vsm.z > 0.5) {
                            vsmDebug += seen < -1.5 ? vec3(1.0, 0.0, 1.0) : (seen < -0.5 ? vec3(1.0, 0.0, 0.0) : vec3(0.0, seen, 1.0 - seen));
                        }
                    }
                    Lo += pbr_shade_sphere(s, Lc, Ls, radiance, wrap) * vis;
                    if (thickness > 0.0) {
                        float t = pow(clamp(dot(s.V, -Lc), 0.0, 1.0), 2.0);
                        transmitted += s.albedo * radiance * t * thickness * vis;
                    }
                }
            }
        }
    }

    vec3 ambient = vec3(0.0);
    {
        float NdotV = max(dot(s.N, s.V), 0.0);
        vec3 R = normalize(reflect(-s.V, s.N));

        vec3 F = fresnel_schlick_roughness(s.F0, NdotV, s.roughness);
        vec3 kD = (vec3(1.0) - F) * (1.0 - s.metallic);

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

        // the moonlit and starlit sky the night probes were baked without
        vec3 night = u_night_ambient.rgb * mix(u_night_ambient.w, 1.0, s.N.y * 0.5 + 0.5);
        diffuseIBL += night * s.albedo;

        vec3 diffuse = kD * diffuseIBL;
        specIBL = pbr_dielectric_spec_limit(specIBL, diffuse, s.metallic, s.roughness);
        ambient = diffuse + specIBL;
    }

    vec3 color = (Lo + ambient) * s.ao + transmitted + s.emissive;
    color = fog_apply_rays(color, gbuffer.relative, v_uv);
    // the debug tints are display colours: lift them into the scene so the curve hands them back
    if (u_shadow.z > 0.5 && u_shadow.y > 0.5) {
        int cascade = csm_pick(s.P);
        vec3 tint = vec3(1.0, 0.0, 0.0);
        if (cascade == 1) {
            tint = vec3(0.0, 1.0, 0.0);
        } else if (cascade == 2) {
            tint = vec3(0.0, 0.0, 1.0);
        } else if (cascade == 3) {
            tint = vec3(1.0, 0.0, 1.0);
        } else if (cascade == 4) {
            tint = vec3(0.0, 1.0, 1.0);
        }
        color += display_linear(tint * 0.15);
    }
    if (u_vsm.z > 0.5 && dot(vsmDebug, vsmDebug) > 0.0) {
        color = display_linear(clamp(vsmDebug, 0.0, 1.0));
    }
    fragment_color = vec4(color, 1.0);
}
