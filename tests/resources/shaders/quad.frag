#version 450

layout(location = 0) in vec2 vUv;
layout(location = 0) out vec4 FragColor;

layout(std140, set = 0, binding = 0) uniform QuadParams {
    vec4 color;
};

void main()
{
    FragColor = vec4(vUv, color.b, 1.0);
}
