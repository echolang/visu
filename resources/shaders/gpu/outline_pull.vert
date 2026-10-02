#version 450

#pragma visu variant skinned SKINNED=1

// visu::graphics::GpuScene's outline mask draw: model_pull.vert's vertex, with the uv, the
// meshlet's material for the cutout and the instance's outline style slot (flags bits 8..10)
layout(location = 0) out vec2 v_uv;
layout(location = 1) flat out uint v_material;
layout(location = 2) flat out float v_style;

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

void main()
{
    uint index = uint(gl_VertexIndex);
    SceneDrawItem item = drawItems[index >> 6u];
    uint at = detail[item.head.x + (index & 63u)];
    vec3 position = vec3(uintBitsToFloat(words[at]), uintBitsToFloat(words[at + 1u]), uintBitsToFloat(words[at + 2u]));
    mat4 model = scene_world(poses[item.head.y]);
#ifdef SKINNED
    uint j = words[at + SCENE_WORD_JOINTS];
    uvec4 joints = uvec4(j & 0xFFu, (j >> 8u) & 0xFFu, (j >> 16u) & 0xFFu, j >> 24u);
    vec4 weights = unpackUnorm4x8(words[at + SCENE_WORD_WEIGHTS]);
    model = model * skin_matrix(joints, weights, uintBitsToFloat(item.head.w));
#endif
    vec4 world = model * vec4(position, 1.0);
    v_uv = vec2(uintBitsToFloat(words[at + SCENE_WORD_UV]), uintBitsToFloat(words[at + SCENE_WORD_UV + 1u]));
    v_material = item.head.z;
    v_style = float((item.extra.z >> SCENE_OUTLINE_SHIFT) & 7u);
    gl_Position = u_projection_view * world;
}
