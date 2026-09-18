#version 450

layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 FragColor;

layout(std140, set = 0, binding = 0) uniform DeferredViewData {
    // x mode: 0 albedo, 1 normal, 2 gray, 3 position, 4 emissive, 5 ssao
    // y gray channel 0..2
    vec4 u_params;
};

layout(set = 1, binding = 0) uniform sampler2D gbuffer_position;
layout(set = 1, binding = 1) uniform sampler2D gbuffer_normal;
layout(set = 1, binding = 2) uniform sampler2D gbuffer_albedo;
layout(set = 1, binding = 3) uniform sampler2D gbuffer_material;
layout(set = 1, binding = 4) uniform sampler2D gbuffer_emissive;
layout(set = 1, binding = 5) uniform sampler2D gbuffer_ao;

void main()
{
    float mode = u_params.x;
    vec4 s = texture(gbuffer_albedo, v_uv);
    vec3 rgb = s.rgb;

    if (mode > 0.5 && mode < 1.5) {
        s = texture(gbuffer_normal, v_uv);
        rgb = s.xyz * 0.5 + 0.5;
    } else if (mode > 1.5 && mode < 2.5) {
        s = texture(gbuffer_material, v_uv);
        float ch = u_params.y;
        float g = s.r;
        if (ch > 0.5 && ch < 1.5) {
            g = s.g;
        } else if (ch > 1.5) {
            g = s.b;
        }
        rgb = vec3(g);
    } else if (mode > 2.5 && mode < 3.5) {
        s = texture(gbuffer_position, v_uv);
        rgb = fract(abs(s.xyz));
    } else if (mode > 3.5 && mode < 4.5) {
        s = texture(gbuffer_emissive, v_uv);
        rgb = s.rgb;
    } else if (mode > 4.5) {
        float g = texture(gbuffer_ao, v_uv).r;
        rgb = vec3(g);
    }

    FragColor = vec4(clamp(rgb, 0.0, 1.0), 1.0);
}
