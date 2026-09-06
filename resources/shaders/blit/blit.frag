#version 450

layout(location = 0) in vec2 vUv;
layout(location = 0) out vec4 FragColor;

layout(set = 1, binding = 0) uniform sampler2D u_texture;

void main()
{
    FragColor = texture(u_texture, vUv);
}
