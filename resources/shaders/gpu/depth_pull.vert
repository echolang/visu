#version 450

#pragma visu variant alpha ALPHA=1
#pragma visu variant vsm VSM=1
#pragma visu variant vsm_alpha VSM=1 ALPHA=1

// visu::graphics::GpuScene's depth draw: no vertex streams. Every draw item (meshlet,
// instance, view) is SCENE_ITEM_VERTICES vertices; this one's triangle is fetched from the
// mesh arena and placed with the instance's world matrix, skinned by the frame palette when
// the model is. A triangle past the meshlet's end is sent outside the clip volume. The view's
// camera is at slot 1, as for shadow.vert, and the math is shadow.vert's
#ifdef ALPHA
// only the cut-out bucket's fragment reads the uv, and the material it cuts out by
layout(location = 0) out vec2 v_uv;
layout(location = 1) flat out uint v_material;
#endif

#ifdef VSM
// a shadow atlas page: the triangle is placed in the light's face, cropped to the page and
// moved into the page's atlas cell, and four clip planes keep it inside that cell
out gl_PerVertex {
    vec4 gl_Position;
    float gl_ClipDistance[4];
};
#endif

#include "visu/camera.glsl"
#include "visu/skin.glsl"
#include "visu/scene.glsl"

layout(std430, set = 2, binding = 0) readonly buffer Words {
    uint words[];
};

layout(std430, set = 2, binding = 1) readonly buffer Detail {
    uint detail[];
};

layout(std430, set = 2, binding = 2) readonly buffer Meshlets {
    SceneMeshlet meshlets[];
};

layout(std430, set = 2, binding = 3) readonly buffer Instances {
    SceneInstance instances[];
};

layout(std430, set = 2, binding = 4) readonly buffer Poses {
    ScenePose poses[];
};

layout(std430, set = 2, binding = 5) readonly buffer Items {
    uvec4 items[];
};

#ifdef VSM
#include "visu/vsm.glsl"
#include "visu/light_gpu.glsl"

layout(std430, set = 2, binding = 6) readonly buffer LightTableBuffer {
    LightGpu lights[];
};

layout(std430, set = 2, binding = 7) readonly buffer Dirty {
    uvec4 dirty[];
};
#endif

void main()
{
    uint vertex = uint(gl_VertexIndex);
    uvec4 item = items[vertex / SCENE_ITEM_VERTICES];
    uint corner = vertex % SCENE_ITEM_VERTICES;
    SceneMeshlet c = meshlets[item.x];
    if (corner / 3u >= c.range.z) {
#ifdef ALPHA
        v_uv = vec2(0.0);
        v_material = 0u;
#endif
        gl_Position = vec4(2.0, 2.0, 2.0, 1.0);
#ifdef VSM
        gl_ClipDistance[0] = -1.0;
        gl_ClipDistance[1] = -1.0;
        gl_ClipDistance[2] = -1.0;
        gl_ClipDistance[3] = -1.0;
#endif
        return;
    }

    SceneInstance inst = instances[item.y];

    uint at = SCENE_CORNER(detail, c, corner / 3u, corner % 3u);
    vec3 position = vec3(uintBitsToFloat(words[at]), uintBitsToFloat(words[at + 1u]), uintBitsToFloat(words[at + 2u]));
#ifdef ALPHA
    v_uv = vec2(uintBitsToFloat(words[at + SCENE_WORD_UV]), uintBitsToFloat(words[at + SCENE_WORD_UV + 1u]));
    v_material = c.material.y;
#endif
    mat4 model = scene_world(poses[inst.meta.z]);
    if ((c.range.w & SCENE_MESHLET_SKINNED) != 0u) {
        uint j = words[at + SCENE_WORD_JOINTS];
        uvec4 joints = uvec4(j & 0xFFu, (j >> 8u) & 0xFFu, (j >> 16u) & 0xFFu, j >> 24u);
        vec4 weights = unpackUnorm4x8(words[at + SCENE_WORD_WEIGHTS]);
        model = model * skin_matrix(joints, weights, inst.hi.w);
    }

    vec4 world = model * vec4(position, 1.0);
#ifdef VSM
    uvec4 page = dirty[item.z];
    vec4 pr = lights[page.y].position_radius;
    uint face;
    uint mip;
    uvec2 xy;
    vsm_page_of(page.z, face, mip, xy);
    vec3 v = vsm_view(face, world.xyz - pr.xyz);
    vec4 rect = vsm_page_rect(mip, xy);
    vec4 cell = vsm_scratch_rect(item.z);
    // clip xy = atlas ndc * w, linear in the face-space x, y and depth
    vec2 scale = (cell.zw - cell.xy) / (rect.zw - rect.xy);
    vec2 clipXY = cell.xy * v.z + (v.xy - rect.xy * v.z) * scale;
    vec2 zw = vsm_clip_zw(v.z, pr.w);
    gl_Position = vec4(clipXY, zw);
    gl_ClipDistance[0] = clipXY.x - cell.x * v.z;
    gl_ClipDistance[1] = cell.z * v.z - clipXY.x;
    gl_ClipDistance[2] = clipXY.y - cell.y * v.z;
    gl_ClipDistance[3] = cell.w * v.z - clipXY.y;
#else
    gl_Position = u_projection_view * world;
#endif
}
