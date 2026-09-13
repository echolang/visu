#version 450

layout(location = 0) in vec2 vUv;
layout(location = 0) out vec4 FragColor;

layout(std140, set = 0, binding = 0) uniform LodParams {
    // x is the mip level to sample
    vec4 level;
};

layout(set = 1, binding = 0) uniform sampler2D uTexture;

void main()
{
    FragColor = vec4(textureLod(uTexture, vUv, level.x).rgb, 1.0);
}
