#version 450

layout(location = 0) in vec2 v_uv;
layout(location = 1) flat in float v_style;

layout(location = 0) out vec4 o_mask;

// visu::graphics::ModelMaterialData, one upload per material batch
layout(std140, set = 0, binding = 0) uniform ModelMaterialData {
    // rgb albedo fallback, a alpha cutoff (0 = opaque)
    vec4 u_base_color;
    vec4 u_factors;
    vec4 u_uv_scale;
};

#include "visu/camera.glsl"

layout(set = 1, binding = 0) uniform sampler2D map_albedo;
layout(set = 1, binding = 5) uniform sampler2D map_alpha;
// OUTLINE_DEPTH_SLOT: the GBuffer depth the scene drew
layout(set = 1, binding = 8) uniform sampler2D u_scene_depth;

const int MAP_ALBEDO = 1;
const int MAP_ALPHA = 32;
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
    vec2 uv = v_uv * u_uv_scale.xy;
    int flags = int(u_factors.z + 0.5);
    float alpha = 1.0;
    if ((flags & MAP_ALBEDO) != 0) {
        alpha = texture(map_albedo, uv).a;
    }
    if ((flags & MAP_ALPHA) != 0) {
        alpha = texture(map_alpha, uv).r;
    }
    if (u_base_color.a > 0.0 && alpha < u_base_color.a) {
        discard;
    }

    float scene = texelFetch(u_scene_depth, ivec2(gl_FragCoord.xy), 0).r;
    float mine = eye_distance(gl_FragCoord.z);
    float front = eye_distance(scene);
    // the same surface drew the scene depth, so allow rounding plus a sliver of distance
    float visible = mine <= front + 0.05 + front * 0.01 ? 1.0 : 0.0;
    o_mask = vec4(1.0, visible, (v_style + 0.5) / OUTLINE_STYLES, 1.0);
}
