#version 450

layout(location = 0) in vec2 vPos;
layout(location = 1) in vec2 vUv;
layout(location = 2) in vec4 vShape;

layout(location = 0) out vec4 FragColor;

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

layout(set = 1, binding = 0) uniform sampler2D uTex;

float sdRoundBox(vec2 p, vec2 b, float r)
{
    vec2 q = abs(p) - b + vec2(r, r);
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

void main()
{
    vec4 color = inner;
    float cover = 1.0;

    int typ = int(stroke.x + 0.5);
    if (vShape.w > 0.5) {
        float d = sdRoundBox(vUv, vShape.xy, vShape.z);
        cover = clamp(0.5 - d / max(fwidth(d), 0.0001), 0.0, 1.0);
    } else if (typ != 2) {
        cover = clamp(vUv.x, 0.0, 1.0);
    }
    vec2 pt = vec2(
        paint0.x * vPos.x + paint0.z * vPos.y + paint1.x,
        paint0.y * vPos.x + paint0.w * vPos.y + paint1.y);
    if (typ == 0) {
        float d = sdRoundBox(pt, extent.xy, extent.z);
        float t = 0.0;
        if (extent.w > 0.0001) {
            t = clamp((d + extent.w * 0.5) / extent.w, 0.0, 1.0);
        } else if (d > 0.0) {
            t = 1.0;
        }
        color = mix(inner, outer, t);
    } else if (typ == 1) {
        vec2 uv = pt / max(extent.xy, vec2(0.0001, 0.0001));
        color = texture(uTex, uv) * inner;
    } else if (typ == 2) {
        color = inner * texture(uTex, vUv).r;
    } else if (typ == 3) {
        float t = clamp(pt.x / max(extent.x, 0.0001), 0.0, 1.0);
        color = mix(inner, outer, t);
    } else if (typ == 4) {
        float t = clamp((length(pt) - extent.z) / max(extent.w, 0.0001), 0.0, 1.0);
        color = mix(inner, outer, t);
    }

    float scScale = scissorExt.w;
    if (scScale > 0.5) {
        vec2 sc = vec2(
            scissor0.x * vPos.x + scissor0.z * vPos.y + scissor1.x,
            scissor0.y * vPos.x + scissor0.w * vPos.y + scissor1.y);
        float sd = sdRoundBox(sc, scissorExt.xy, scissorExt.z);
        float a = clamp(0.5 - sd * scScale, 0.0, 1.0);
        color *= a;
    }

    FragColor = color * cover;
}
