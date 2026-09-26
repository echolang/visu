#version 450

// an 8 x 8 grid of quads, coloured from a storage buffer by instance
layout(location = 0) in vec3 aPos;
layout(location = 0) flat out vec4 vColor;

layout(std430, set = 2, binding = 0) readonly buffer Cells {
    vec4 colors[];
};

void main()
{
    int i = gl_InstanceIndex;
    vec2 cell = vec2(float(i % 8), float(i / 8)) * 0.25 - 1.0;
    vColor = colors[i];
    gl_Position = vec4(aPos.xy + cell, 0.0, 1.0);
}
