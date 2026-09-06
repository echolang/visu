#version 450

#pragma visu variant a TEST=1
#pragma visu variant b TEST=2

layout(location = 0) in vec4 pcolor;
layout(location = 0) out vec4 fragment_color;

void main()
{
    fragment_color = pcolor;
}
