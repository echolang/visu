/**
 * The GPU scene the depth views are culled and drawn from. Mirrors visu::graphics
 * SceneClusterGpu, SceneInstanceGpu, SceneModelGpu and SceneViewGpu (std430, no implicit
 * padding: every struct is whole vec4 rows).
 */
#ifndef VISU_SCENE_GLSL
#define VISU_SCENE_GLSL

// triangles per cluster; a draw item expands to this many, the tail degenerate
#define SCENE_CLUSTER_TRIANGLES 64u
#define SCENE_ITEM_VERTICES 192u

#define SCENE_CLUSTER_SKINNED 1u
#define SCENE_BUCKET_NONE 0xFFFFFFFFu

#define SCENE_INSTANCE_LIVE 1u
#define SCENE_INSTANCE_CASTS 2u
#define SCENE_INSTANCE_SKINNED 4u

// a GPU-written view holding nothing this frame
#define SCENE_PASS_NONE 0xFFFFFFFFu

// an item's instance with this bit set is a mover row (dynamic or skinned), not a static
#define SCENE_MOVER_BIT 0x80000000u

struct SceneCluster {
    // model-space centre, radius
    vec4 sphere;
    // x first arena index, y triangles, z shadow bucket, w flags
    uvec4 range;
};

struct SceneInstance {
    mat4 world;
    // xyz world bounds min, w the instance lod bias
    vec4 lo;
    // xyz world bounds max, w the first skin palette row
    vec4 hi;
    // x scene model, y flags
    uvec4 meta;
};

struct SceneModel {
    // x lod count, y flags, z words per vertex
    uvec4 head;
    // x model lod bias, y cull distance (0 = never)
    vec4 bias;
    // switch-in distance of lod 0..7
    vec4 dist0;
    vec4 dist1;
    // first cluster of lod 0..7; the end of the last level follows it
    uvec4 start0;
    uvec4 start1;
};

struct SceneView {
    vec4 planes[6];
    // x the pass this view draws in, y kind
    uvec4 meta;
};

// a SceneView row in words, and the word of its meta.x, for kernels that write views raw
#define SCENE_VIEW_WORDS 28u
#define SCENE_VIEW_META 24u

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

// visu::geo::Frustum.contains(AABB): outside only when the p-vertex is behind a plane
bool scene_box_visible(SceneView v, vec3 lo, vec3 hi)
{
    for (int i = 0; i < 6; i++) {
        vec4 p = v.planes[i];
        vec3 corner = vec3(
            p.x >= 0.0 ? hi.x : lo.x,
            p.y >= 0.0 ? hi.y : lo.y,
            p.z >= 0.0 ? hi.z : lo.z
        );
        if (p.x * corner.x + p.y * corner.y + p.z * corner.z + p.w < 0.0) {
            return false;
        }
    }
    return true;
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
    return true;
}

#endif
