#version 450

layout(location = 0) in vec2 vUv;
layout(location = 0) out vec4 FragColor;

layout(set = 1, binding = 0) uniform sampler2DArray uArray;

void main()
{
    FragColor = vec4(texture(uArray, vec3(vUv, 1.0)).rgb, 1.0);
}
