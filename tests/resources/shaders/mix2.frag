#version 450

layout(location = 0) in vec2 vUv;
layout(location = 0) out vec4 FragColor;

layout(set = 1, binding = 0) uniform sampler2D texA;
layout(set = 1, binding = 1) uniform sampler2D texB;

void main()
{
    vec3 a = texture(texA, vUv).rgb;
    vec3 b = texture(texB, vUv).rgb;
    FragColor = vec4(a * 0.5 + b * 0.5, 1.0);
}
