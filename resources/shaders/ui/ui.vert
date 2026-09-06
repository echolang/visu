#version 450

layout(location = 0) in vec2 aPos;
layout(location = 1) in vec2 aUv;
layout(location = 2) in vec4 aShape;
layout(location = 3) in vec4 aColor;
layout(location = 4) in vec4 aClip;

layout(location = 0) out vec2 vPos;
layout(location = 1) out vec2 vUv;
layout(location = 2) out vec4 vShape;
layout(location = 3) out vec4 vColor;
layout(location = 4) out vec4 vClip;

layout(std140, set = 0, binding = 0) uniform UiFrame
{
    vec4 view;
};

void main()
{
    vPos = aPos;
    vUv = aUv;
    vShape = aShape;
    vColor = aColor;
    vClip = aClip;
    vec2 vp = view.xy;
    gl_Position = vec4(
        2.0 * aPos.x / vp.x - 1.0,
        1.0 - 2.0 * aPos.y / vp.y,
        0.0,
        1.0);
}
