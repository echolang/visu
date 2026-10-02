#version 450

#pragma visu variant skinned SKINNED=1
#pragma visu variant parallax MODEL_PARALLAX=1
#pragma visu variant skinned_parallax SKINNED=1 MODEL_PARALLAX=1
// the depth pre-pass reuses this program unchanged (PREPASS is the fragment's): the same code
// gives the same positions, which the shading pass's depth-equal test relies on
#pragma visu variant prepass PREPASS=1
#pragma visu variant skinned_prepass SKINNED=1 PREPASS=1

// visu::graphics::GpuScene's G-buffer draw: no vertex streams. Every index the triangle stage
// wrote is `(item << 6) | local`: the draw item, whose record (SceneDrawItem) names the meshlet's
// vertex list, the pose row, the material and the tint, and a meshlet-local vertex, whose arena
// word offset the vertex list holds. The vertex is placed with the instance's world matrix, skinned by the frame palette when the model is, and leaves exactly what
// pbr/model.vert hands model.frag, plus the meshlet's material for the table
layout(location = 0) out vec3 v_position;
layout(location = 1) out vec3 v_normal;
layout(location = 2) out vec4 v_tangent;
layout(location = 3) out vec2 v_uv;
layout(location = 4) out vec4 v_tint;
layout(location = 5) flat out uint v_material;

#include "visu/camera.glsl"
#ifdef SKINNED
#include "visu/skin.glsl"
#endif
#include "visu/scene.glsl"

layout(std430, set = 2, binding = 0) readonly buffer Words {
    uint words[];
};

layout(std430, set = 2, binding = 1) readonly buffer Detail {
    uint detail[];
};

layout(std430, set = 2, binding = 4) readonly buffer Poses {
    ScenePose poses[];
};

layout(std430, set = 2, binding = 5) readonly buffer DrawItems {
    SceneDrawItem drawItems[];
};

vec3 word3(uint at)
{
    return vec3(uintBitsToFloat(words[at]), uintBitsToFloat(words[at + 1u]), uintBitsToFloat(words[at + 2u]));
}

void main()
{
    uint index = uint(gl_VertexIndex);
    SceneDrawItem item = drawItems[index >> 6u];
    uint at = detail[item.head.x + (index & 63u)];

    vec3 position = word3(at);
    vec2 uv = vec2(uintBitsToFloat(words[at + SCENE_WORD_UV]), uintBitsToFloat(words[at + SCENE_WORD_UV + 1u]));
    vec3 normal = word3(at + SCENE_WORD_NORMAL);
    vec4 tangent = vec4(word3(at + SCENE_WORD_TANGENT), uintBitsToFloat(words[at + SCENE_WORD_TANGENT + 3u]));

    mat4 model = scene_world(poses[item.head.y]);
#ifdef SKINNED
    uint j = words[at + SCENE_WORD_JOINTS];
    uvec4 joints = uvec4(j & 0xFFu, (j >> 8u) & 0xFFu, (j >> 16u) & 0xFFu, j >> 24u);
    vec4 weights = unpackUnorm4x8(words[at + SCENE_WORD_WEIGHTS]);
    model = model * skin_matrix(joints, weights, uintBitsToFloat(item.head.w));
#endif
    vec4 world = model * vec4(position, 1.0);
    mat3 rotation = mat3(model);

    v_position = world.xyz;
    // mat3(model), not the inverse transpose: models are placed with uniform scale
    v_normal = normalize(rotation * normal);
    v_tangent = vec4(normalize(rotation * tangent.xyz), tangent.w);
    v_uv = uv;
    v_tint = vec4(unpackHalf2x16(item.extra.x), unpackHalf2x16(item.extra.y));
    v_material = item.head.z;

    gl_Position = u_projection_view * world;
}
