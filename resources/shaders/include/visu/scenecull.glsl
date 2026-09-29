/**
 * The uniforms and counter layout every scene culling kernel shares. Mirrors
 * visu::graphics::SceneCullParams and the SCENE_COUNTER_* constants of GpuScene.
 */
#ifndef VISU_SCENECULL_GLSL
#define VISU_SCENECULL_GLSL

#include "visu/scene.glsl"

layout(std140, set = 0, binding = 0) uniform SceneCullParams {
    // xyz the play eye every lod is picked from, w the global lod bias
    vec4 u_eye;
    // x static rows, y mover rows, z views, w buckets
    uvec4 u_rows;
    // x most pairs, y most items, z mode (0 count, 1 write), w passes
    uvec4 u_limits;
};

// counters: pairs, pairs dropped, items dropped, then per segment count, cursor and end
#define SCENE_COUNTER_PAIRS 0u
#define SCENE_COUNTER_PAIRS_DROPPED 1u
#define SCENE_COUNTER_ITEMS_DROPPED 2u
#define SCENE_SEGMENTS_MAX 1024u
#define SCENE_COUNT_BASE 4u
#define SCENE_CURSOR_BASE (4u + SCENE_SEGMENTS_MAX)
#define SCENE_END_BASE (4u + 2u * SCENE_SEGMENTS_MAX)

// args: the cluster dispatch, then one draw per segment
#define SCENE_ARGS_DRAW_BASE 4u

#define SCENE_BUCKETS_MAX 128u

#endif
