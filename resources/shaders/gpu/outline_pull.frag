#version 450
#extension GL_EXT_nonuniform_qualifier : require

// pbr/outline_mask.frag for the GPU-driven outline draw: the cutout reads the meshlet's material
// from the table, the style slot comes from the instance
layout(location = 0) in vec2 v_uv;
layout(location = 1) flat in uint v_material;
layout(location = 2) flat in float v_style;

layout(location = 0) out vec4 o_mask;

#include "visu/bindless.glsl"
#include "visu/material_table.glsl"
#include "visu/camera.glsl"

// OUTLINE_DEPTH_SLOT: the GBuffer depth the scene drew
layout(set = 1, binding = 8) uniform sampler2D u_scene_depth;

const float OUTLINE_STYLES = 4.0;

// metres from the eye for a 0..1 depth, through the camera's own projection
float eye_distance(float depth)
{
    vec4 view = u_inverse_projection * vec4(0.0, 0.0, depth, 1.0);
    return -view.z / view.w;
}

void main()
{
    // cut-out foliage has to outline its leaves, not its cards
    if (table_alpha_cutout(materials[v_material], v_uv)) {
        discard;
    }

    float scene = texelFetch(u_scene_depth, ivec2(gl_FragCoord.xy), 0).r;
    float mine = eye_distance(gl_FragCoord.z);
    float front = eye_distance(scene);
    // the same surface drew the scene depth, so allow rounding plus a sliver of distance
    float visible = mine <= front + 0.05 + front * 0.01 ? 1.0 : 0.0;
    o_mask = vec4(1.0, visible, (v_style + 0.5) / OUTLINE_STYLES, 1.0);
}
