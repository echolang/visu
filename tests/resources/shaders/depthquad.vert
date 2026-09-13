#version 450

layout(location = 0) in vec3 aPos;
layout(location = 1) in vec2 aUv;

layout(std140, set = 0, binding = 0) uniform DepthParams {
    mat4 projectionView;
    vec4 color;
    vec4 place;
};

void main()
{
    vec3 p = vec3(aPos.xy * place.w + place.xy, place.z);
    gl_Position = projectionView * vec4(p, 1.0);
}
