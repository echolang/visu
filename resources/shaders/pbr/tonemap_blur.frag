#version 450

#pragma visu variant base TONEMAP_BLUR_BASE=1

// One axis of a separable Gaussian over `u_tm_pass.w` slices of 64 x 32 cells laid side by side
// (slice s is columns 64 s to 64 s + 63). Taps clamp inside the slices, so a cell at a slice's
// edge never reads the neighbouring one.
//
// The bilateral grid is 64 slices of (w V, w) in rg: x and y are wide (the base should not
// follow texture), z narrow (the edges it should follow are a few slices apart). `base` is the
// wide Gaussian on one slice of log luminance in r: alone it would halo, mixed into the grid it
// keeps the grid from ringing along smooth gradients (cloud, shade, a specular falloff). It
// sums r alone, so its arithmetic is the scalar one it always was.

layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 frag_blur;

#include "visu/tonemap_uniforms.glsl"

layout(set = 1, binding = 0) uniform sampler2D u_source;

#ifdef TONEMAP_BLUR_BASE
#define TONEMAP_BLUR_T float
#define TONEMAP_BLUR_TAP(at) texelFetch(u_source, at, 0).r
#define TONEMAP_BLUR_OUT(v) vec4(v, 0.0, 0.0, 1.0)
#else
#define TONEMAP_BLUR_T vec2
#define TONEMAP_BLUR_TAP(at) texelFetch(u_source, at, 0).rg
#define TONEMAP_BLUR_OUT(v) vec4(v, 0.0, 1.0)
#endif

void main()
{
    ivec2 p = ivec2(gl_FragCoord.xy);
    int slice = p.x / 64;
    ivec3 at = ivec3(p.x % 64, p.y, slice);
    int axis = int(u_tm_pass.x + 0.5);
    int radius = int(u_tm_pass.z + 0.5);
    float k = -0.5 / max(u_tm_pass.y * u_tm_pass.y, 1e-4);
    ivec3 step = ivec3(axis == 0 ? 1 : 0, axis == 1 ? 1 : 0, axis == 2 ? 1 : 0);
    ivec3 top = ivec3(63, 31, int(u_tm_pass.w + 0.5) - 1);
    TONEMAP_BLUR_T sum = TONEMAP_BLUR_T(0.0);
    float total = 0.0;
    for (int i = -radius; i <= radius; ++i) {
        ivec3 q = clamp(at + step * i, ivec3(0), top);
        float w = exp(float(i * i) * k);
        sum += TONEMAP_BLUR_TAP(ivec2(q.z * 64 + q.x, q.y)) * w;
        total += w;
    }
    frag_blur = TONEMAP_BLUR_OUT(sum / total);
}
