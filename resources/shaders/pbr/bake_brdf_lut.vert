#version 450

/*
 * The one fullscreen program that does NOT flip v: the LUT is indexed
 * by (NdotV, roughness) in the light pass, so its rows must run the
 * way the integration writes them.
 */
layout(location = 0) in vec3 a_position;
layout(location = 1) in vec2 a_uv;

layout(location = 0) out vec2 v_uv;

void main()
{
    gl_Position = vec4(a_position, 1.0);
    v_uv = a_uv;
}
