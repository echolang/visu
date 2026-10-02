#version 450
#extension GL_EXT_nonuniform_qualifier : require

// the TextureTable check: each quarter of the target reads a different table slot, picked per
// pixel from u_slots, so the index is non-uniform across the draw
#include "visu/bindless.glsl"

layout(std140, set = 0, binding = 0) uniform TableParams {
    uvec4 u_slots;
};

layout(location = 0) in vec2 vUv;
layout(location = 0) out vec4 FragColor;

void main()
{
    uint quarter = min(uint(vUv.x * 4.0), 3u);
    FragColor = table_sample(u_slots[quarter], 0u, vec2(0.5));
}
