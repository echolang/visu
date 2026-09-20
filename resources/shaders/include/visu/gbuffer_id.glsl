/**
 * Kind in the GBuffer id attachment (r8, code / 255). Keep in lockstep with
 * visu::graphics::GBufferId.
 */
#ifndef VISU_GBUFFER_ID_GLSL
#define VISU_GBUFFER_ID_GLSL

const uint GBUFFER_ID_NONE = 0u;
const uint GBUFFER_ID_OPAQUE = 1u;
const uint GBUFFER_ID_TERRAIN = 2u;
const uint GBUFFER_ID_GRASS = 3u;
const uint GBUFFER_ID_FOLIAGE = 4u;
const uint GBUFFER_ID_UNLIT = 5u;

uint gbuffer_id_decode(float t)
{
    return uint(t * 255.0 + 0.5);
}

float gbuffer_id_encode(uint id)
{
    return float(id) / 255.0;
}

bool gbuffer_id_soft_ao(uint id)
{
    return id == GBUFFER_ID_GRASS || id == GBUFFER_ID_FOLIAGE;
}

float gbuffer_id_wrap(uint id)
{
    if (id == GBUFFER_ID_GRASS) {
        return 0.55;
    }
    if (id == GBUFFER_ID_FOLIAGE) {
        return 0.20;
    }
    return 0.0;
}

float gbuffer_id_thickness(uint id)
{
    if (id == GBUFFER_ID_GRASS) {
        return 0.55;
    }
    if (id == GBUFFER_ID_FOLIAGE) {
        return 0.25;
    }
    return 0.0;
}

vec3 gbuffer_id_color(uint id)
{
    if (id == GBUFFER_ID_NONE) {
        return vec3(0.0);
    }
    if (id == GBUFFER_ID_OPAQUE) {
        return vec3(0.55, 0.55, 0.58);
    }
    if (id == GBUFFER_ID_TERRAIN) {
        return vec3(0.45, 0.38, 0.22);
    }
    if (id == GBUFFER_ID_GRASS) {
        return vec3(0.25, 0.85, 0.30);
    }
    if (id == GBUFFER_ID_FOLIAGE) {
        return vec3(0.15, 0.55, 0.20);
    }
    if (id == GBUFFER_ID_UNLIT) {
        return vec3(1.0, 0.2, 0.8);
    }
    return vec3(1.0, 1.0, 0.0);
}

#endif
