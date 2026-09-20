#ifndef PBR_SHADE_GLSL
#define PBR_SHADE_GLSL

#include "visu/functions/brdf.glsl"
#include "visu/pbr/surface.glsl"
#include "visu/constants.glsl"

/**
 * Peak channel. Cheaper than Rec.709 luma and still catches a hot sky lobe.
 */
float pbr_peak(vec3 c)
{
    return max(c.r, max(c.g, c.b));
}

/**
 * Dark dielectrics: F0 0.04 already outruns Lambert albedo/PI, so split-sum
 * IBL and GGX read as a coating. Fade spec toward diffuse as roughness
 * rises. Metals and smooth dielectrics keep their highlights.
 */
vec3 pbr_dielectric_spec_limit(vec3 spec, vec3 diffuse, float metallic, float roughness)
{
    float specL = pbr_peak(spec);
    float cap = max(pbr_peak(diffuse), 0.02);
    float scale = min(1.0, cap / max(specL, 1e-5));
    return spec * mix(1.0, scale, (1.0 - metallic) * roughness);
}

vec3 pbr_lit(in PBRSurface s, vec3 L, vec3 radiance, float NdotL)
{
    vec3 H = normalize(s.V + L);

    // energy conservation
    vec3 F;
    vec3 spec = pbr_specular(s.N, s.V, H, L, s.F0, s.roughness, F);
    vec3 kD = (vec3(1.0) - F) * (1.0 - s.metallic);
    vec3 diff = kD * s.albedo / PI;
    spec = pbr_dielectric_spec_limit(spec, diff, s.metallic, s.roughness);

    return (diff + spec) * radiance * NdotL;
}

vec3 pbr_shade(in PBRSurface s, vec3 L, vec3 radiance)
{
    return pbr_lit(s, L, radiance, max(dot(s.N, L), 0.0));
}

vec3 pbr_shade_wrapped(in PBRSurface s, vec3 L, vec3 radiance, float wrap)
{
    float NdotL = max(dot(s.N, L), 0.0) + wrap * max(dot(-s.N, L), 0.0);
    return pbr_lit(s, L, radiance, NdotL);
}

#endif
