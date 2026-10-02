#version 450

layout(location = 0) in vec3 aPos;
layout(location = 0) out vec2 vUv;

void main()
{
    vUv = aPos.xy * 0.5 + 0.5;
    gl_Position = vec4(aPos.x, aPos.y, 0.0, 1.0);
}
