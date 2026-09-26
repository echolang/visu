#version 450

#pragma visu variant skinned SKINNED=1

// cooked model vertex (visu::graphics::ModelVertex), then the instance stream:
// four model matrix columns and the per-instance tint; skinned adds joints, weights and the
// palette base (visu::graphics::SkinnedVertex, SkinInstanceData)
layout(location = 0) in vec3 a_position;
layout(location = 1) in vec3 a_normal;
layout(location = 2) in vec4 a_tangent;
layout(location = 3) in vec2 a_uv;
layout(location = 4) in vec4 a_model0;
layout(location = 5) in vec4 a_model1;
layout(location = 6) in vec4 a_model2;
layout(location = 7) in vec4 a_model3;
layout(location = 8) in vec4 a_tint;
#ifdef SKINNED
layout(location = 9) in uvec4 a_joints;
layout(location = 10) in vec4 a_weights;
layout(location = 11) in vec4 a_skin;
#endif

layout(location = 0) out vec3 v_position;
layout(location = 1) out vec3 v_normal;
layout(location = 2) out vec4 v_tangent;
layout(location = 3) out vec2 v_uv;
layout(location = 4) out vec4 v_tint;

#include "visu/camera.glsl"
#ifdef SKINNED
#include "visu/skin.glsl"
#endif

void main()
{
    mat4 model = mat4(a_model0, a_model1, a_model2, a_model3);
#ifdef SKINNED
    model = model * skin_matrix(a_joints, a_weights, a_skin.x);
#endif
    vec4 world = model * vec4(a_position, 1.0);
    mat3 rotation = mat3(model);

    v_position = world.xyz;
    // mat3(model), not the inverse transpose: models are placed with uniform scale
    v_normal = normalize(rotation * a_normal);
    v_tangent = vec4(normalize(rotation * a_tangent.xyz), a_tangent.w);
    v_uv = a_uv;
    v_tint = a_tint;

    gl_Position = u_projection_view * world;
}
