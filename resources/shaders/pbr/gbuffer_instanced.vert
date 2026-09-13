#version 450

layout(location = 0) in vec3 a_position;
layout(location = 1) in vec3 a_normal;
// instance stream: model matrix then the packed material
layout(location = 2) in vec4 a_model0;
layout(location = 3) in vec4 a_model1;
layout(location = 4) in vec4 a_model2;
layout(location = 5) in vec4 a_model3;
layout(location = 6) in vec4 a_albedo_metallic;
layout(location = 7) in vec4 a_emissive_roughness;

layout(location = 0) out vec3 v_position;
layout(location = 1) out vec3 v_normal;
layout(location = 2) out vec4 v_albedo_metallic;
layout(location = 3) out vec4 v_emissive_roughness;

#include "visu/camera.glsl"

void main()
{
    mat4 model = mat4(a_model0, a_model1, a_model2, a_model3);
    vec4 world = model * vec4(a_position, 1.0);

    v_position = world.xyz;
    // mat3(model), not the inverse transpose: non-uniform scale would skew
    v_normal = normalize(mat3(model) * a_normal);
    v_albedo_metallic = a_albedo_metallic;
    v_emissive_roughness = a_emissive_roughness;

    gl_Position = u_projection_view * world;
}
