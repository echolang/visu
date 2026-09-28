/**
 * Light-shaft march and resolve uniforms at slot 0. Mirrors
 * visu::graphics::GodRayUniforms; std140 with mat4 and vec4 members only.
 */
#ifndef VISU_GODRAYS_UNIFORMS_GLSL
#define VISU_GODRAYS_UNIFORMS_GLSL

#include "visu/camera.glsl"
#include "visu/screen.glsl"
#include "visu/godrays_common.glsl"

#define GODRAY_MAX_STEPS 64

layout(std140, set = 0, binding = 0) uniform GodRayUniforms {
    mat4 u_gr_light_space[5];
    // last frame's projection times view
    mat4 u_gr_prev_projection_view;
    // far view Z of cascades 0 to 3
    vec4 u_gr_splits;
    // xyz direction the key light travels, w far view Z of cascade 4
    vec4 u_gr_key;
    // x steps, y max distance, z frame jitter, w fog density at the eye
    vec4 u_gr_march;
    // x fog height falloff, y history weight, z 1 history usable, w depth rejection
    vec4 u_gr_medium;
    // shaft target width, height, 1 / width, 1 / height
    vec4 u_gr_target;
    // xyz last frame's eye, w fog start distance (the air nearer stays clear)
    vec4 u_gr_prev_camera;
};

/**
 * World direction from the eye through `uv` of the screen.
 */
vec3 godrays_view_dir(vec2 uv)
{
    vec4 p = u_inverse_projection_view * vec4(ndc_from_uv(uv), 0.5, 1.0);
    return normalize(p.xyz / p.w - u_camera_position.xyz);
}

#endif
