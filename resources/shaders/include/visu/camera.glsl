/**
 * Camera uniforms at slot 1. Mirrors visu::graphics::CameraUniforms;
 * std140 with mat4 and vec4 members only, so the Echo struct needs no
 * padding. Published by CameraSystem, pushed by GBufferPass.
 */
#ifndef VISU_CAMERA_GLSL
#define VISU_CAMERA_GLSL

layout(std140, set = 0, binding = 1) uniform CameraUniforms {
    mat4 u_projection;
    mat4 u_view;
    mat4 u_projection_view;
    mat4 u_inverse_projection;
    mat4 u_inverse_projection_view;
    // xyz world position of the camera
    vec4 u_camera_position;
    // width, height, 1/width, 1/height in device pixels
    vec4 u_resolution;
};

#endif
