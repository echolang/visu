/**
 * Vertex stage for anything drawn as a sky: a unit cube around the
 * camera with the translation dropped, pushed to the far plane so
 * every piece of geometry wins the depth test.
 */
layout(location = 0) in vec3 a_position;
layout(location = 0) out vec3 v_direction;

#include "visu/camera.glsl"

void main()
{
    v_direction = a_position;
    // drop the translation: the sky never moves closer
    mat4 view = mat4(mat3(u_view));
    vec4 clip = u_projection * view * vec4(a_position, 1.0);
    // z = w puts the sky on the far plane, so any geometry wins
    gl_Position = clip.xyww;
}
