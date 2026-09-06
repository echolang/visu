#version 450

#pragma visu variant a TEST=1
#pragma visu variant b TEST=2

layout(location = 0) in vec3 position;
layout(location = 1) in vec3 color;
layout(location = 0) out vec4 pcolor;

void main()
{
    pcolor = vec4(color, 1.0);
    gl_Position = vec4(position, 1.0);
}
