#version 450

layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 FragColor;

layout(std140, set = 0, binding = 0) uniform LoadingData {
    vec4 u_time;
};

void main()
{
    float t = u_time.x;
    vec2 uv = v_uv;
    vec2 p = uv * 2.0 - 1.0;
    p.x *= 1.7777778;
    float v = length(p);
    vec3 dusk = vec3(0.07, 0.05, 0.04);
    vec3 clay = vec3(0.18, 0.11, 0.07);
    vec3 leaf = vec3(0.10, 0.20, 0.12);
    float wave = 0.5 + 0.5 * sin(t * 0.35 + uv.y * 3.2);
    vec3 col = mix(dusk, clay, uv.y);
    col = mix(col, leaf, 0.18 * wave * (1.0 - uv.y));
    col *= 1.0 - 0.48 * smoothstep(0.35, 1.45, v);
    vec2 blob = p - vec2(sin(t * 0.28) * 0.42, cos(t * 0.22) * 0.18);
    col += vec3(0.10, 0.07, 0.03) * exp(-dot(blob, blob) * 3.8);
    FragColor = vec4(col, 1.0);
}
