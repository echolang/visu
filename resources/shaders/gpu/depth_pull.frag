#version 450

#pragma visu variant alpha ALPHA=1

// visu::graphics::GpuScene's depth draw. The opaque bucket writes depth only; the alpha
// variant is shadow.frag: the bucket's material at slot 0 and its maps decide the discard
#ifdef ALPHA
layout(location = 0) in vec2 v_uv;

#include "visu/alpha_cutout.glsl"
#endif

void main()
{
#ifdef ALPHA
    if (alpha_cutout(v_uv)) {
        discard;
    }
#endif
}
