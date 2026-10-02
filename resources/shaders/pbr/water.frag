#version 450

layout(location = 0) in vec3 v_world;
layout(location = 1) in vec3 v_local;
layout(location = 2) in vec2 v_uv;
layout(location = 3) in vec4 v_plane;
layout(location = 4) in vec4 v_absorption;
layout(location = 5) in vec4 v_ripple;
layout(location = 6) in vec4 v_flow;
layout(location = 7) in vec4 v_extra;
layout(location = 8) in vec4 v_body;

layout(location = 0) out vec4 fragment_color;

#include "visu/camera.glsl"
#include "visu/constants.glsl"
#include "visu/functions/brdf.glsl"
#include "visu/shadow.glsl"

vec3 water_sphere_l(vec3 toLight, vec3 V, vec3 N, float sourceRadius)
{
    vec3 R = reflect(-V, N);
    vec3 centerToRay = dot(toLight, R) * R - toLight;
    float rayDist = length(centerToRay);
    vec3 closest = toLight;
    if (rayDist > 1e-4) {
        closest = toLight + centerToRay * clamp(sourceRadius / rayDist, 0.0, 1.0);
    }
    return normalize(closest);
}

// Fog at slot 3; slot 0 is the water uniform. The shafts here are marched to the bed, so
// the water looks them up itself (`water_fog_rays`) and hands the result to the shared fog.
#define VISU_FOG_SKY_SLOT 3
#define VISU_AERIAL_SLOT 4
#include "visu/fog.glsl"
#include "visu/godrays.glsl"
#include "visu/light_gpu.glsl"

layout(std140, set = 0, binding = 2) uniform LightUniforms {
    vec4 u_sun_direction;
    vec4 u_sun_color;
    vec4 u_ibl;
    mat4 u_light_space[5];
    vec4 u_splits;
    vec4 u_shadow;
    vec4 u_moon_direction;
    vec4 u_moon_color;
    vec4 u_night_ambient;
    vec4 u_cluster_head;
    vec4 u_cluster_z;
    // x 1 when the shadow atlas is bound, y its mip bias, z 1 paints the debug view (the light
    // pass only), w the shadow distance
    vec4 u_vsm;
};

#include "visu/lights.glsl"
#include "visu/vsm_sample.glsl"

layout(set = 1, binding = 0) uniform sampler2D u_scene;
layout(set = 1, binding = 1) uniform sampler2D u_bed;
layout(set = 1, binding = 2) uniform sampler2D u_mirror;
layout(set = 1, binding = 7) uniform samplerCube u_prefilter;
layout(set = 1, binding = 11) uniform sampler2DArray shadowmap;
// legacy: fog_color of fog.glsl, with the sun's azimuth from the light block
vec3 water_fog_color(vec3 dir)
{
    if (u_fog_color.w < 0.5) {
        return u_fog_color.rgb;
    }

    vec2 uv = fog_sky_uv(fog_sky_horizon(dir, -u_sun_direction.xyz));
    return u_fog_color.rgb * (textureLod(u_fog_sky, uv, 0.0).rgb + u_fog_floor.rgb);
}

// legacy: fog_apply of fog.glsl, with the lights' directions from the light block
vec3 water_fog(vec3 color, vec3 relative)
{
    if (u_fog_density.w < 0.5) {
        return color;
    }
    float len = length(relative);
    if (len < 1e-3) {
        return color;
    }
    float cutoff = u_fog_params.y;
    if (cutoff > 0.0 && len > cutoff) {
        return color;
    }
    vec3 dir = relative / len;
    float dy = dir.y;
    float start = u_fog_params.x;
    float optical = fog_integral(dy, len);
    float t = max(exp(-(optical - fog_integral(dy, min(len, start)))), 1.0 - u_fog_density.z);
    float td = exp(-(optical - fog_integral(dy, min(len, start + u_fog_params.w))));
    vec3 sunDir = normalize(-u_sun_direction.xyz);
    float sun = pow(max(dot(dir, sunDir), 0.0), max(u_fog_sun.w, 1.0));
    vec3 moonDir = normalize(-u_moon_direction.xyz);
    float moon = pow(max(dot(dir, moonDir), 0.0), max(u_fog_moon.w, 1.0));
    vec3 glow = u_fog_sun.rgb * sun + u_fog_moon.rgb * moon;
    vec3 fog = water_fog_color(dir) * (1.0 - t) + glow * (1.0 - td);
    return color * t + fog;
}

vec3 water_fog_rays_legacy(vec3 color, vec3 relative, vec2 uv);

// the fog over the water at `relative`, with this frame's light shafts at `uv`: the shared
// fog, the shafts looked up at the bed's distance and kept to the part in front of the surface
vec3 water_fog_rays(vec3 color, vec3 relative, vec2 uv)
{
    if (u_fog_model.w < 0.5) {
        return water_fog_rays_legacy(color, relative, uv);
    }
    if (u_fog_shafts.w < 0.5) {
        return fog_apply(color, relative);
    }
    float len = length(relative);
    if (len < 1e-3) {
        return color;
    }
    vec3 dir = relative / len;
    vec4 bed = texture(u_bed, uv);
    float bedDist = bed.a >= 0.5 ? length(bed.xyz) : GODRAY_SKY_DEPTH;
    vec2 shaft = godrays_fetch(uv, bedDist);
    shaft.x *= clamp(len / max(bedDist, 1e-3), 0.0, 1.0);
    float lit = mix(1.0, shaft.y, u_fog_shafts.y);
    bool moonKey = u_fog_shaft_light.w > 0.5;
    vec3 toLight = moonKey ? u_fog_to_moon.xyz : u_fog_model.xyz;
    float phase = godrays_phase2(dot(dir, toLight), u_fog_shaft_phase.xyz);
    vec3 rays = u_fog_shaft_light.rgb * (phase * shaft.x * u_fog_shafts.x);
    float lit_sun = moonKey ? 1.0 : lit;
    float lit_moon = moonKey ? lit : 1.0;
    return fog_surface(color, relative, lit_sun, lit_moon, rays);
}

// legacy: water_fog with this frame's light shafts. Without the shafts bound it is water_fog.
vec3 water_fog_rays_legacy(vec3 color, vec3 relative, vec2 uv)
{
    if (u_fog_shafts.w < 0.5) {
        return water_fog(color, relative);
    }
    if (u_fog_density.w < 0.5) {
        return color;
    }
    float len = length(relative);
    if (len < 1e-3) {
        return color;
    }
    float cutoff = u_fog_params.y;
    if (cutoff > 0.0 && len > cutoff) {
        return color;
    }
    vec3 dir = relative / len;
    float dy = dir.y;
    float start = u_fog_params.x;
    float optical = fog_integral(dy, len);
    float t = max(exp(-(optical - fog_integral(dy, min(len, start)))), 1.0 - u_fog_density.z);
    float td = exp(-(optical - fog_integral(dy, min(len, start + u_fog_params.w))));
    // the shaft texels here were marched to the bed under the surface: look them up at the
    // bed's distance, then keep only the part of S in front of the surface
    vec4 bed = texture(u_bed, uv);
    float bedDist = bed.a >= 0.5 ? length(bed.xyz) : GODRAY_SKY_DEPTH;
    vec2 shaft = godrays_fetch(uv, bedDist);
    shaft.x *= clamp(len / max(bedDist, 1e-3), 0.0, 1.0);
    float occlude = mix(1.0, shaft.y, u_fog_shafts.y);
    vec3 sunDir = normalize(-u_sun_direction.xyz);
    float sun = pow(max(dot(dir, sunDir), 0.0), max(u_fog_sun.w, 1.0));
    vec3 moonDir = normalize(-u_moon_direction.xyz);
    float moon = pow(max(dot(dir, moonDir), 0.0), max(u_fog_moon.w, 1.0));
    vec3 glow = (u_fog_sun.rgb * sun + u_fog_moon.rgb * moon) * occlude;
    vec3 fog = water_fog_color(dir) * (1.0 - t) + glow * (1.0 - td);
    vec3 toLight = u_fog_shaft_light.w > 0.5 ? moonDir : sunDir;
    float phase = godrays_phase2(dot(dir, toLight), u_fog_shaft_phase.xyz);
    vec3 rays = u_fog_shaft_light.rgb * (phase * shaft.x * u_fog_shafts.x);
    return color * t + fog + rays;
}

// One long wave. A phase that jumps by more than a pixel is dropped, so the
// far field does not alias.
float water_slope(vec2 dir, vec2 p, float k, float phase)
{
    float theta = dot(dir, p) * k + phase;
    float fw = length(vec2(dFdx(theta), dFdy(theta)));
    float atten = 1.0 - smoothstep(1.0, 2.8, fw);
    return cos(theta) * atten;
}

vec3 ripple_normal(vec3 planeN, vec3 world, float time)
{
    float wavelength = max(v_ripple.x, 0.05);
    float amp = v_ripple.z;
    vec2 flow = v_flow.xy;
    float fl = length(flow);
    vec2 dir = vec2(0.86, 0.51);
    if (fl > 1e-3) {
        dir = flow / fl;
    }
    vec2 side = vec2(-dir.y, dir.x);
    float k = 6.2831853 / wavelength;
    float phase = time * v_ripple.y * 6.2831853;
    vec2 p = world.xz;
    vec2 a = dir;
    vec2 b = normalize(dir * 0.45 + side);
    vec2 c = normalize(side * 0.8 - dir * 0.3);
    vec2 slope = vec2(0.0);
    slope += a * water_slope(a, p, k, phase) * amp;
    slope += b * water_slope(b, p, k * 1.73, phase * 0.71) * (amp * 0.45);
    slope += c * water_slope(c, p, k * 0.57, phase * 1.2) * (amp * 0.28);
    vec3 T = vec3(1.0, 0.0, 0.0) - planeN * planeN.x;
    if (dot(T, T) < 1e-4) {
        T = vec3(0.0, 0.0, 1.0) - planeN * planeN.z;
    }
    T = normalize(T);
    vec3 B = normalize(cross(planeN, T));
    float gT = dot(T.xz, slope);
    float gB = dot(B.xz, slope);
    return normalize(planeN - T * gT - B * gB);
}

void main()
{
    if (v_flow.w > 0.5 && dot(v_local.xz, v_local.xz) > 0.25) {
        discard;
    }

    vec3 planeN = normalize(v_plane.xyz);
    vec3 N = ripple_normal(planeN, v_world, v_extra.y);
    vec3 V = normalize(u_camera_position.xyz - v_world);
    // Facing the plane, not the ripple. The peak stays low so a grazing view
    // keeps the bed; a full mirror was turning the basin into the meadow.
    float facing = max(dot(planeN, V), 0.0);
    float fresnel = mix(0.04, 0.28, pow(1.0 - facing, 5.0));
    float rough = clamp(v_ripple.w, 0.02, 1.0);

    vec2 pixel = gl_FragCoord.xy / max(u_resolution.xy, vec2(1.0));
    vec2 slide = N.xz * v_flow.z;
    vec2 refrUv = clamp(pixel + slide, vec2(0.0), vec2(1.0));
    vec4 bedSample = texture(u_bed, refrUv);
    vec3 bed = bedSample.rgb + u_camera_position.xyz;
    float thickness = 6.0;
    float side = dot(planeN, bed) + v_plane.w;
    if (bedSample.a > 0.5 && side < 0.0) {
        thickness = max(distance(v_world, bed), 0.0);
    }
    vec3 transmit = exp(-v_absorption.rgb * v_absorption.a * thickness);

    vec3 L = normalize(-u_sun_direction.xyz);
    vec3 Lm = normalize(-u_moon_direction.xyz);
    // the cascades belong to the brighter of sun and moon
    bool moonKey = u_moon_color.w > 0.5;
    float keyVis = 1.0;
    if (u_shadow.y > 0.5) {
        float viewZ = (u_view * vec4(v_world, 1.0)).z;
        int cascade = csm_index(viewZ, u_splits);
        vec3 keyDir = moonKey ? u_moon_direction.xyz : u_sun_direction.xyz;
        keyVis = 1.0 - shadow_sample(shadowmap, v_world, N, normalize(keyDir), u_light_space[cascade], cascade);
    }
    float sunVis = moonKey ? 1.0 : keyVis;
    float moonVis = moonKey ? keyVis : 1.0;
    float ndotl = max(dot(N, L), 0.0);

    // The water body scatters sun, moon and sky back to the eye; with depth that colour takes
    // over from the bed. Without it a light basin reads as bare stone under clear glass.
    float maxLodBody = max(u_ibl.x - 1.0, 0.0);
    vec3 skyAmbient = textureLod(u_prefilter, vec3(0.0, 1.0, 0.0), maxLodBody).rgb + u_night_ambient.rgb;
    vec3 sunIn = u_sun_color.rgb * u_sun_direction.w * max(L.y, 0.0) * sunVis;
    vec3 moonIn = u_moon_color.rgb * u_moon_direction.w * max(Lm.y, 0.0) * moonVis;
    vec3 bodyRadiance = v_body.rgb * ((sunIn + moonIn) / PI + skyAmbient);
    float clear = exp(-v_body.w * thickness);
    vec3 refr = mix(bodyRadiance, texture(u_scene, refrUv).rgb * transmit, clear);
    refr *= 1.0 + 0.35 * pow(ndotl, 6.0) * sunVis;

    vec2 mirrorUv = pixel + slide * 0.65;
    float inside = 1.0;
    if (mirrorUv.x < 0.0 || mirrorUv.y < 0.0 || mirrorUv.x > 1.0 || mirrorUv.y > 1.0) {
        inside = 0.0;
    }
    vec3 mirror = texture(u_mirror, clamp(mirrorUv, vec2(0.0), vec2(1.0))).rgb;
    vec3 R = normalize(reflect(-V, N));
    // The probe's horizon is the grass. Lift the ray into the sky.
    vec3 skyR = normalize(vec3(R.x, max(R.y, 0.45), R.z));
    float maxLod = max(u_ibl.x - 1.0, 0.0);
    vec3 ibl = textureLod(u_prefilter, skyR, max(rough, 0.55) * maxLod).rgb;
    // the night probes hold no moonlit sky; add the hemisphere the light pass uses
    ibl += u_night_ambient.rgb;
    float mirrorWeight = v_extra.x * inside * (1.0 - rough);
    vec3 reflected = mix(ibl, mirror, mirrorWeight);

    vec3 spec = vec3(0.0);
    vec3 F0 = vec3(0.02);
    {
        vec3 H = normalize(V + L);
        vec3 fres;
        vec3 sunSpec = pbr_specular(N, V, H, L, F0, rough, fres);
        vec3 radiance = u_sun_color.rgb * u_sun_direction.w;
        spec += sunSpec * radiance * ndotl * sunVis;
    }

    if (u_moon_direction.w > 0.0) {
        vec3 H = normalize(V + Lm);
        vec3 fres;
        vec3 moonSpec = pbr_specular(N, V, H, Lm, F0, rough, fres);
        vec3 radiance = u_moon_color.rgb * u_moon_direction.w;
        spec += moonSpec * radiance * max(dot(N, Lm), 0.0) * moonVis;
    }

    {
        float viewDepth = -(u_view * vec4(v_world, 1.0)).z;
        uvec2 range = light_range(viewDepth, u_cluster_head, u_cluster_z);
        if (range.x <= range.y) {
            vec2 px = min(pixel * u_resolution.xy, u_resolution.xy - vec2(1.0));
            uint base = light_tile_base(px, u_cluster_head);
            // the world size of one screen pixel here, which picks the shadow page level
            float footprint = vsm_footprint(viewDepth, u_projection[1][1], u_resolution.y);
            for (uint w = range.x >> 5u; w <= (range.y >> 5u); w++) {
                uint bits = light_word(base, w, range);
                while (bits != 0u) {
                    uint b = uint(findLSB(bits));
                    bits &= bits - 1u;
                    uint slot = light_slot(w * 32u + b);
                    LightGpu l = u_lights[slot];
                    vec4 pr = l.position_radius;
                    vec3 toLight = pr.xyz - v_world;
                    float dist = length(toLight);
                    if (dist >= pr.w) {
                        continue;
                    }
                    vec3 Lc = toLight / max(dist, 1e-4);
                    // outside a spot's cone: no light, so no shadow lookup either
                    float cone = light_cone(l, -Lc);
                    if (cone <= 0.0) {
                        continue;
                    }
                    vec3 radiance = light_radiance(l, dist, u_cluster_z.w) * cone;
                    vec3 Ls = water_sphere_l(toLight, V, N, l.source.x);
                    vec3 H = normalize(V + Ls);
                    vec3 fres;
                    vec3 one = pbr_specular(N, V, H, Ls, F0, rough, fres);
                    float vis = 1.0;
                    float fade = vsm_light_fade(l, u_camera_position.xyz, u_vsm);
                    if (fade > 0.0) {
                        vis = mix(1.0, vsm_visibility(slot, pr.xyz, pr.w, v_world + N * l.source.z, footprint, u_vsm.y), fade);
                    }
                    spec += one * radiance * max(dot(N, Lc), 0.0) * vis;
                }
            }
        }
    }

    // scene, mirror, probe and body are all linear radiance here; the tone-map pass encodes
    vec3 color = mix(refr, reflected, fresnel) + spec;
    color = water_fog_rays(color, v_world - u_camera_position.xyz, gl_FragCoord.xy * u_resolution.zw);
    fragment_color = vec4(color, 1.0);
}
