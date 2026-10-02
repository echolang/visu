/**
 * The GPU scene every GPU-driven view is culled and drawn from. Mirrors visu::graphics
 * SceneMeshletGpu, SceneRunGpu, SceneInstanceGpu, ScenePoseGpu, SceneModelGpu, SceneChunkGpu and
 * SceneViewGpu (std430, no implicit padding: every struct is whole vec4 rows). Every instance
 * names its first pose row, which always holds its world matrix: a static's exact one, a mover's
 * resolved for the frame (`scene_resolve`) from the previous and current poses in the two rows
 * after it. Every instance has one candidate source: the member list of its spatial chunk, or
 * the active set (`SCENE_INSTANCE_ACTIVE`).
 */
#ifndef VISU_SCENE_GLSL
#define VISU_SCENE_GLSL

// triangles per meshlet; a depth draw item expands to this many, the tail degenerate
#define SCENE_MESHLET_TRIANGLES 64u
#define SCENE_ITEM_VERTICES 192u

#define SCENE_MESHLET_SKINNED 1u
#define SCENE_BUCKET_NONE 0xFFFFFFFFu

// arena vertex words: position 0, uv 3, normal 5, tangent 8, joints 12, weights 13
#define SCENE_WORD_UV 3u
#define SCENE_WORD_NORMAL 5u
#define SCENE_WORD_TANGENT 8u
#define SCENE_WORD_JOINTS 12u
#define SCENE_WORD_WEIGHTS 13u

#define SCENE_INSTANCE_LIVE 1u
#define SCENE_INSTANCE_CASTS 2u
#define SCENE_INSTANCE_SKINNED 4u
// the pose block holds a previous and a current pose the frame resolves between
#define SCENE_INSTANCE_MOVING 8u
// drawn in the main view and the mirror
#define SCENE_INSTANCE_MAIN 16u
// drawn into the outline mask, in the style slot of bits 8..10
#define SCENE_INSTANCE_OUTLINE 32u
// a candidate of the active set, not of its chunk
#define SCENE_INSTANCE_ACTIVE 64u
#define SCENE_OUTLINE_SHIFT 8u

// a GPU-written view holding nothing this frame
#define SCENE_PASS_NONE 0xFFFFFFFFu

// view flags: the clip plane, the reach sphere and the normal cone test apply
#define SCENE_VIEW_CLIP 1u
#define SCENE_VIEW_SPHERE 2u
#define SCENE_VIEW_CONE 4u

// a chunk pair naming a block of the active set instead of a chunk
#define SCENE_ACTIVE_BLOCK 0x80000000u
#define SCENE_ACTIVE_BLOCK_ROWS 256u

struct SceneMeshlet {
    // model-space centre, radius
    vec4 sphere;
    // normal cone axis, w sine cutoff (1 never culls)
    vec4 cone;
    // x first vertex-list entry, y first triangle word (both in the detail buffer), z
    // triangles, w flags
    uvec4 range;
    // x shadow bucket, y material, z G-buffer class, w vertices
    uvec4 material;
};

// consecutive meshlets of one level sharing class and bucket
struct SceneRun {
    // x first meshlet, y meshlets, z G-buffer class, w shadow bucket
    uvec4 range;
};

// the arena word offset of a meshlet's packed triangle `t`, corner `k`, read from `detail`
#define SCENE_CORNER(detail, m, t, k) detail[(m).range.x + ((detail[(m).range.y + (t)] >> (8u * (k))) & 0xFFu)]

// what a G-buffer set's vertex program reads per draw item, written by scene_triangles: x the
// meshlet's first vertex-list entry, y the instance's pose row, z the material, w the palette base
// (float bits); then the tint halves and the instance flags
struct SceneDrawItem {
    uvec4 head;
    uvec4 extra;
};

struct SceneInstance {
    // xyz world bounds min, w the instance lod bias
    vec4 lo;
    // xyz world bounds max, w the first skin palette row
    vec4 hi;
    // x scene model, y flags, z first pose row (the world matrix), w spatial chunk
    uvec4 meta;
    // x tint rg, y tint ba (two halves each)
    uvec4 extra;
};

// the affine rows of a world matrix; for a mover's previous and current pose rows instead
// position (xyz), orientation (quaternion) and scale (xyz)
struct ScenePose {
    vec4 r0;
    vec4 r1;
    vec4 r2;
};

// the world matrix a pose row holds, column-major as the CPU's Mat4
mat4 scene_world(ScenePose p)
{
    return mat4(
        vec4(p.r0.x, p.r1.x, p.r2.x, 0.0),
        vec4(p.r0.y, p.r1.y, p.r2.y, 0.0),
        vec4(p.r0.z, p.r1.z, p.r2.z, 0.0),
        vec4(p.r0.w, p.r1.w, p.r2.w, 1.0)
    );
}

vec4 scene_tint(SceneInstance inst)
{
    return vec4(unpackHalf2x16(inst.extra.x), unpackHalf2x16(inst.extra.y));
}

struct SceneModel {
    // x lod count, y flags, z words per vertex
    uvec4 head;
    // x model lod bias, y cull distance (0 = never)
    vec4 bias;
    // switch-in distance of lod 0..7
    vec4 dist0;
    vec4 dist1;
    // first run of lod 0..7; the end of the last level follows it
    uvec4 start0;
    uvec4 start1;
};

// a spatial chunk: the box its members reach, their slice of the member list and the union of
// their flags
struct SceneChunk {
    vec4 lo;
    vec4 hi;
    // x first member, y members, z flags of every member or'ed, w the largest member's
    // bounding radius (float bits)
    uvec4 range;
};

struct SceneView {
    vec4 planes[6];
    // x the pass this view draws in, y instance flags it requires beyond its set's, z view
    // flags, w the smallest instance radius it draws (float bits; 0 draws all): a sun cascade
    // skips casters under one of its texels
    uvec4 meta;
    // SCENE_VIEW_CLIP: a seventh plane (the mirror's water)
    vec4 clip;
    // SCENE_VIEW_SPHERE: the instance box has to reach within w of xyz (the mirror's reach)
    vec4 sphere;
    // SCENE_VIEW_CONE: the eye the meshlet normal cones are tested from; w the screen-size
    // factor, pixels a radius must cover over the focal length in pixels (0 draws all)
    vec4 eye;
};

// a SceneView row in words, and the word of its meta.x, for kernels that write views raw
#define SCENE_VIEW_WORDS 40u
#define SCENE_VIEW_META 24u
// the word of its sphere.x
#define SCENE_VIEW_SPHERE_WORD 32u
// the word of its eye.w, the screen-size factor (0 draws all)
#define SCENE_VIEW_SCREEN 39u

float scene_lod_distance(SceneModel m, uint i)
{
    if (i < 4u) {
        return m.dist0[i];
    }
    return m.dist1[i - 4u];
}

uint scene_lod_start(SceneModel m, uint i)
{
    if (i < 4u) {
        return m.start0[i];
    }
    return m.start1[i - 4u];
}

// whether the box has a corner on the front of plane `p`: the p-vertex test
bool scene_box_front(vec4 p, vec3 lo, vec3 hi)
{
    vec3 corner = vec3(
        p.x >= 0.0 ? hi.x : lo.x,
        p.y >= 0.0 ? hi.y : lo.y,
        p.z >= 0.0 ? hi.z : lo.z
    );
    return p.x * corner.x + p.y * corner.y + p.z * corner.z + p.w >= 0.0;
}

// visu::geo::Frustum.contains(AABB): outside only when the p-vertex is behind a plane
bool scene_box_visible(SceneView v, vec3 lo, vec3 hi)
{
    for (int i = 0; i < 6; i++) {
        if (!scene_box_front(v.planes[i], lo, hi)) {
            return false;
        }
    }
    return true;
}

// the view's extra tests on a box: the clip plane (visu::graphics::waterAbove) and the reach
// sphere, as the mirror's CPU cull ran them
bool scene_box_reached(SceneView v, vec3 lo, vec3 hi)
{
    if ((v.meta.z & SCENE_VIEW_CLIP) != 0u && !scene_box_front(v.clip, lo, hi)) {
        return false;
    }

    if ((v.meta.z & SCENE_VIEW_SPHERE) != 0u) {
        vec3 c = v.sphere.xyz;
        if (length(clamp(c, lo, hi) - c) > v.sphere.w) {
            return false;
        }
    }

    return true;
}

// whether something of bounding radius `r` inside the box covers fewer than the view's minimum
// pixels from the view's eye wherever in the box it stands: r under eye.w times the distance
// to the box's nearest point
bool scene_too_small(SceneView v, vec3 lo, vec3 hi, float r)
{
    if (v.eye.w <= 0.0) {
        return false;
    }

    vec3 e = v.eye.xyz;
    return r < v.eye.w * length(clamp(e, lo, hi) - e);
}

// whether the sphere (`c`, `r`) lies wholly behind plane `p`: the one test of
// visu::geo::Frustum.contains(center, radius). A caller walks its planes with it rather than
// passing them in, which would copy the array
bool scene_sphere_behind(vec4 p, vec3 c, float r)
{
    return dot(p.xyz, c) + p.w < -r;
}

bool scene_sphere_visible(SceneView v, vec3 c, float r)
{
    for (int i = 0; i < 6; i++) {
        if (scene_sphere_behind(v.planes[i], c, r)) {
            return false;
        }
    }

    if ((v.meta.z & SCENE_VIEW_CLIP) != 0u && scene_sphere_behind(v.clip, c, r)) {
        return false;
    }
    return true;
}

// the meshlet faces away from `eye` everywhere: the normal cone test against the bounding
// sphere (centre `c`, radius `r`, world cone `axis`, sine cutoff `cutoff`)
bool scene_cone_backfacing(vec3 eye, vec3 c, float r, vec3 axis, float cutoff)
{
    vec3 d = c - eye;
    return dot(d, axis) >= cutoff * length(d) + r;
}

#endif
