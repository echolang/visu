#version 450

layout(location = 0) in vec2 aPos;
layout(location = 1) in vec2 aUv;
layout(location = 2) in vec4 aShape;

layout(location = 0) out vec2 vPos;
layout(location = 1) out vec2 vUv;
layout(location = 2) out vec4 vShape;

layout(std140, set = 0, binding = 0) uniform Vg
{
    vec4 view;
    vec4 inner;
    vec4 outer;
    vec4 scissorExt;
    vec4 scissor0;
    vec4 scissor1;
    vec4 paint0;
    vec4 paint1;
    vec4 extent;
    vec4 stroke;
};

void main()
{
    vPos = aPos;
    vUv = aUv;
    vShape = aShape;
    vec2 vp = view.xy;
    gl_Position = vec4(
        2.0 * aPos.x / vp.x - 1.0,
        1.0 - 2.0 * aPos.y / vp.y,
        0.0,
        1.0);
}
