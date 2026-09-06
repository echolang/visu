#version 450

layout(location = 0) in vec2 vPos;
layout(location = 1) in vec2 vUv;
layout(location = 2) in vec4 vShape;
layout(location = 3) in vec4 vColor;
layout(location = 4) in vec4 vClip;

layout(location = 0) out vec4 FragColor;

layout(std140, set = 0, binding = 0) uniform UiFrame
{
    vec4 view;
};

layout(set = 1, binding = 0) uniform sampler2D uTex;

float sdRoundBox(vec2 p, vec2 b, float r)
{
    vec2 q = abs(p) - b + vec2(r, r);
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

void main()
{
    vec4 color = vColor;
    float cover = 1.0;
    if (vShape.w > 2.5) {
        float d = abs(sdRoundBox(vUv, vShape.xy, vShape.z)) - 1.0;
        cover = clamp(0.5 - d / max(fwidth(d), 0.0001), 0.0, 1.0);
    } else if (vShape.w > 1.5) {
        color = vColor * texture(uTex, vUv).r;
    } else if (vShape.w > 0.5) {
        float d = sdRoundBox(vUv, vShape.xy, vShape.z);
        cover = clamp(0.5 - d / max(fwidth(d), 0.0001), 0.0, 1.0);
    }
    if (vClip.z > 0.5 || vClip.w > 0.5) {
        vec2 p = vPos - vClip.xy;
        float cd = sdRoundBox(p, vClip.zw, 0.0);
        color *= clamp(0.5 - cd / max(fwidth(cd), 0.0001), 0.0, 1.0);
    }
    FragColor = color * cover;
}
