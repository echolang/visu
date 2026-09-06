#version 450

layout(location = 0) in vec3 aPos;
layout(location = 1) in vec2 aUv;
layout(location = 0) out vec2 vUv;

void main()
{
    gl_Position = vec4(aPos, 1.0);
    // mesh.quad is GL-style (v=0 at ndc bottom). vulkan/metal
    // textures are top-left; unflipped v inverts the blit.
    vUv = vec2(aUv.x, 1.0 - aUv.y);
}
