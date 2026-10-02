#version 450

#pragma visu variant alpha ALPHA=1

// visu::graphics::GpuScene's depth draw. The opaque bucket writes depth only; the alpha bucket
// holds every cut-out material and drops a fragment by its own material's cutoff and maps,
// read through the bank's material table and texture table
#ifdef ALPHA
#extension GL_EXT_nonuniform_qualifier : require

layout(location = 0) in vec2 v_uv;
layout(location = 1) flat in uint v_material;

#include "visu/bindless.glsl"
#include "visu/material_table.glsl"
#endif

void main()
{
#ifdef ALPHA
    if (table_alpha_cutout(materials[v_material], v_uv)) {
        discard;
    }
#endif
}
