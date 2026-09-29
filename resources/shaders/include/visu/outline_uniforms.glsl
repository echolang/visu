/**
 * Outline composite uniforms at slot 0. Mirrors visu::graphics::OutlineUniforms; std140 with
 * vec4 members and vec4 arrays only, so the Echo struct needs no padding.
 */
#ifndef VISU_OUTLINE_UNIFORMS_GLSL
#define VISU_OUTLINE_UNIFORMS_GLSL

layout(std140, set = 0, binding = 0) uniform OutlineUniforms {
    // the quad in NDC: min x, min y, max x, max y
    vec4 u_rect;
    // 1 / width, 1 / height of the mask, widest glow in device pixels, unused
    vec4 u_texel;
    vec4 u_colors[4];
    // per style: glow width in device pixels, strength behind an occluder, silhouette fill, unused
    vec4 u_params[4];
};

#endif
