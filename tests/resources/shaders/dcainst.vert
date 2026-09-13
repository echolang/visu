#version 450

layout(location = 0) in vec3 aPos;
layout(location = 1) in vec3 aNormal;
layout(location = 2) in vec4 aModel0;
layout(location = 3) in vec4 aModel1;
layout(location = 4) in vec4 aModel2;
layout(location = 5) in vec4 aModel3;
layout(location = 6) in vec4 aColor;

layout(location = 0) out vec4 vColor;

layout(std140, set = 0, binding = 0) uniform DcaParams {
    mat4 projectionView;
};

void main()
{
    mat4 model = mat4(aModel0, aModel1, aModel2, aModel3);
    vColor = vec4(aColor.rgb + aNormal * 0.0, aColor.a);
    gl_Position = projectionView * model * vec4(aPos, 1.0);
}
