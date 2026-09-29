/**
 * The uniform the light culling kernels share. Mirrors visu::graphics::LightCullParams.
 */
#ifndef VISU_LIGHTCULL_GLSL
#define VISU_LIGHTCULL_GLSL

#include "visu/light_gpu.glsl"

layout(std140, set = 0, binding = 0) uniform LightCullParams {
    // the view's six frustum planes, visu::geo::Frustum order
    vec4 u_planes[6];
    mat4 u_view;
    // xyz eye, w projection scale along x (cot of half the horizontal fov)
    vec4 u_eye;
    // x width, y height (pixels), z tile pixels, w projection scale along y
    vec4 u_screen;
    // x near, y slices per log2 metre, z slices, w tiles across
    vec4 u_zparams;
    // x table rows, y key capacity, z mask words, w tiles down
    uvec4 u_counts;
    // x shadow distance: the lights sorted before this view depth are the ones that may cast
    vec4 u_shadow;
};

#endif
