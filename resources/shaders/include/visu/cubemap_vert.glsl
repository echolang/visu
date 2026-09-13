/**
 * Vertex stage for the cube bakes: draw a unit cube from the inside
 * and interpolate the direction. The capture projection mirrors Y so
 * a face lands the way the cube convention expects on a top-left
 * framebuffer.
 */
layout(location = 0) in vec3 a_position;

layout(location = 0) out vec3 v_position;

#include "visu/capture.glsl"

void main()
{
    v_position = a_position;
    gl_Position = u_capture_projection * u_capture_view * vec4(a_position, 1.0);
}
