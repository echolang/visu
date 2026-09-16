/**
 * Uniforms for the cube bakes at slot 0: the capture view for the
 * face being drawn, plus the knobs the prefilter pass reads.
 * Mirrors visu::graphics::CaptureUniforms.
 */
#ifndef VISU_CAPTURE_GLSL
#define VISU_CAPTURE_GLSL

layout(std140, set = 0, binding = 0) uniform CaptureUniforms {
    mat4 u_capture_projection;
    mat4 u_capture_view;
    // x roughness, y source face resolution, z convolution samples
    vec4 u_capture_params;
};

#endif
