/**
 * The uniform, counter and argument layout every scene culling kernel shares. Mirrors
 * visu::graphics::SceneCullParams and the SCENE_COUNTER_* / SCENE_ARGS_* constants of GpuScene.
 *
 * A cull set runs four stages, each counted, scanned and then written at the scanned offset, so
 * every list comes out in the same order every run:
 *  - chunks (scene_chunks): per view, the chunks whose box meets it and the active set's blocks
 *    of SCENE_ACTIVE_BLOCK_ROWS rows become chunk pairs, view after view. A local set (its
 *    views carry a reach sphere, u_local.x > 0) walks only the window of grid cells round each
 *    view's sphere instead of every occupied chunk;
 *  - members (scene_members): per chunk pair, the instances that pass, one (instance, view,
 *    run) pair per material run of the level they draw at. The counts go to a dense matrix, a
 *    region per pass (its keys times its chunk pairs, scene_matrix_at), key-major inside it, so
 *    after the scan the pairs of one segment (pass x key) are contiguous and in chunk pair
 *    order, and the scan runs over the chunk pairs kept, not the capacity. A depth set's key is the
 *    run's shadow bucket; a G-buffer set's is its class times SCENE_DEPTH_BINS plus the
 *    instance's depth bin, so a class's pairs run near to far;
 *  - meshlets (scene_meshlets): every kept pair's meshlets flattened (their counts scanned), 64
 *    a workgroup; the ones that pass become draw items in that order, pair after pair, so every
 *    segment's items are contiguous too;
 *  - triangles (scene_triangles, G-buffer sets only): every item's triangles as indices.
 * scene_args turns each stage's totals into the next stage's dispatch, and at the end into one
 * indirect draw per segment.
 */
#ifndef VISU_SCENECULL_GLSL
#define VISU_SCENECULL_GLSL

#include "visu/scene.glsl"

layout(std140, set = 0, binding = 0) uniform SceneCullParams {
    // xyz the play eye every lod is picked from, w the global lod bias
    vec4 u_eye;
    // x occupied spatial chunks, y active rows (the active set is chunk row 0), z views, w keys
    // a pass sorts by (shadow buckets, or G-buffer classes)
    uvec4 u_counts;
    // x most chunk pairs, y most pairs, z most items, w most triangles
    uvec4 u_caps;
    // x mode (0 count, 1 write; scene_args: the step), y flags every instance needs, z the
    // depth bins of a G-buffer set (0 for a depth set), w passes
    uvec4 u_mode;
    // x the debug view (SCENE_DEBUG_*), yzw unused
    uvec4 u_debug;
    // the chunk grid: x the world x of its west edge, y the z of its north edge, z metres a
    // cell, w how far a local window reaches past a view's sphere (the chunks' overhang)
    vec4 u_grid;
    // x cells a side of a local set's window (0: every view walks every occupied chunk), y the
    // grid's columns, z its rows, w unused
    uvec4 u_local;
};

// a G-buffer set's debug views: each meshlet tinted a colour hashed from its id
#define SCENE_DEBUG_NONE 0u
#define SCENE_DEBUG_MESHLETS 1u

// counters: the stage totals as kept, what each stage dropped, then one count per view
#define SCENE_COUNTER_CHUNK_PAIRS 0u
#define SCENE_COUNTER_PAIRS 1u
#define SCENE_COUNTER_ITEMS 2u
#define SCENE_COUNTER_TRIANGLES 3u
#define SCENE_COUNTER_DROPPED_CHUNK_PAIRS 4u
#define SCENE_COUNTER_DROPPED_PAIRS 5u
#define SCENE_COUNTER_DROPPED_ITEMS 6u
#define SCENE_COUNTER_DROPPED_TRIANGLES 7u
#define SCENE_COUNTER_VIEW_BASE 8u
#define SCENE_VIEWS_MAX 256u
// each pass's first chunk pair, then the total, past the views (scene_args step 0)
#define SCENE_COUNTER_PASS_BASE (SCENE_COUNTER_VIEW_BASE + SCENE_VIEWS_MAX + 1u)
// the lengths the matrix and the pair count scans run over, written on the GPU
#define SCENE_COUNTER_MATRIX_SCAN (SCENE_COUNTER_PASS_BASE + 6u)
#define SCENE_COUNTER_PAIR_SCAN (SCENE_COUNTER_MATRIX_SCAN + 1u)
// the meshlets the meshlet stage walks (every kept pair's, flattened) and the length of the
// per-workgroup count scans that follow
#define SCENE_COUNTER_WALK (SCENE_COUNTER_PAIR_SCAN + 1u)
#define SCENE_COUNTER_WALK_SCAN (SCENE_COUNTER_WALK + 1u)
// meshlets a set may walk per item it holds (GpuScene SCENE_WALK_PER_ITEM)
#define SCENE_WALK_PER_ITEM 2u

// args: the members, meshlets and triangles dispatches, then one draw per segment
#define SCENE_ARGS_MEMBERS 0u
#define SCENE_ARGS_MESHLETS 4u
#define SCENE_ARGS_TRIANGLES 8u
#define SCENE_ARGS_DRAW_BASE 12u
#define SCENE_DRAW_WORDS 5u

// keys a pass may sort by: G-buffer classes times depth bins
#define SCENE_KEYS_MAX 256u
#define SCENE_SEGMENTS_MAX 128u

// a G-buffer set orders each class's pairs by distance from the play eye, near first, in bins
// that double every two (1.41x apart from 2 m), so foliage stacked deep is drawn front to back
#define SCENE_DEPTH_BINS 16u

uint scene_depth_bin(float d)
{
    float b = floor(log2(max(d, 1.0)) * 2.0) - 2.0;
    return uint(clamp(b, 0.0, float(SCENE_DEPTH_BINS - 1u)));
}

// a G-buffer set's draws are per class, every bin of it in one draw; a depth set's per key
uint scene_draw_keys()
{
    if (u_mode.z == 0u) {
        return u_counts.w;
    }
    return u_counts.w / u_mode.z;
}

// the active set's blocks of SCENE_ACTIVE_BLOCK_ROWS rows, each one chunk stage candidate
uint scene_active_blocks()
{
    return (u_counts.y + SCENE_ACTIVE_BLOCK_ROWS - 1u) / SCENE_ACTIVE_BLOCK_ROWS;
}

// the chunk stage's spatial candidates a view: a local set's window, else every occupied chunk
uint scene_spatial_candidates()
{
    if (u_local.x > 0u) {
        return u_local.x * u_local.x;
    }
    return u_counts.x;
}

// the chunk stage's tiles of 256 candidates a view, at least one (GpuScene sceneChunkTiles)
uint scene_chunk_tiles()
{
    return max((scene_spatial_candidates() + scene_active_blocks() + 255u) / 256u, 1u);
}

// the grid cell of world offset `p` (x, z), clamped to the grid like SceneChunks.at
uvec2 scene_grid_cell(vec2 p)
{
    vec2 f = floor((p - u_grid.xy) / u_grid.z);
    vec2 most = vec2(float(u_local.y - 1u), float(u_local.z - 1u));
    return uvec2(clamp(f, vec2(0.0), most));
}

// the matrix entry of key `k` for chunk pair `cp` of a pass whose chunk pairs start at `first`
// and number `n`: the pass's region starts at keys * first
uint scene_matrix_at(uint first, uint n, uint k, uint cp)
{
    return u_counts.w * first + k * n + (cp - first);
}

#endif
