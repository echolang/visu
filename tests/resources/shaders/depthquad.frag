#version 450

layout(location = 0) out vec4 FragColor;

layout(std140, set = 0, binding = 0) uniform DepthParams {
    mat4 projectionView;
    vec4 color;
    vec4 place;
};

void main()
{
    FragColor = color;
}
