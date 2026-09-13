#version 450

layout(location = 0) in vec3 vPos;
layout(location = 1) in vec4 vColor;
layout(location = 0) out vec4 fragColor;

void main()
{
    float shade = 0.45 + 0.55 * clamp(vPos.y * 0.12 + 0.55, 0.0, 1.0);
    fragColor = vec4(vColor.rgb * shade, 1.0);
}
