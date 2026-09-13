#version 450

layout(location = 0) out vec4 FragColor;

layout(std140, set = 0, binding = 0) uniform CubeParams {
    // xyz sample direction, w mip level
    vec4 dir;
};

layout(set = 1, binding = 0) uniform samplerCube uCube;

void main()
{
    FragColor = vec4(textureLod(uCube, normalize(dir.xyz), dir.w).rgb, 1.0);
}
