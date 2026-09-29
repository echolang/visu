/**
 * The uniform and the state words the shadow atlas kernels share. Mirrors
 * visu::graphics::VsmParams and the VSM_STATE_* layout of ShadowAtlas.
 */
#ifndef VISU_VSMCULL_GLSL
#define VISU_VSMCULL_GLSL

#include "visu/vsm.glsl"
#include "visu/light_gpu.glsl"

layout(std140, set = 0, binding = 0) uniform VsmParams {
    mat4 u_vsm_view;
    // xyz play eye, w projection scale along y
    vec4 u_vsm_eye;
    // x width, y height, z mip bias, w receiver step in pixels
    vec4 u_vsm_screen;
    vec4 u_vsm_cluster_head;
    vec4 u_vsm_cluster_z;
    // x light rows, y frame, z most dirty pages, w changed boxes
    uvec4 u_vsm_counts;
    // x shadow distance: lights farther from the eye light without a shadow
    vec4 u_vsm_shadow;
};

// state: the clear draw, misses per mip, candidates per list, dirty pages, misses dropped
#define VSM_STATE_CLEAR 0u
#define VSM_STATE_MISSES 4u
#define VSM_STATE_CANDIDATES 9u
#define VSM_STATE_DIRTY 12u
#define VSM_STATE_DROPPED 13u
// the pool's own level bias, fixed point 1/256: raised while misses outrun free pages
#define VSM_STATE_BIAS 14u
// the copy dispatch: one workgroup per dirty page
#define VSM_STATE_COPY 16u
#define VSM_STATE_WORDS 20u

#define VSM_MISS_MAX 16384u

// a page unused this long is taken before one used last frame
#define VSM_STALE_FRAMES 60u

#endif
