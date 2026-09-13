/**
 * Vertex stage for a fullscreen pass over Mesh::quad (pos3 uv2).
 * The quad's v runs bottom-up, textures are top-left, so v flips
 * here — every fullscreen program in visu shares this convention.
 * Include once per program.
 */
layout(location = 0) in vec3 a_position;
layout(location = 1) in vec2 a_uv;

layout(location = 0) out vec2 v_uv;

void main()
{
    gl_Position = vec4(a_position, 1.0);
    v_uv = vec2(a_uv.x, 1.0 - a_uv.y);
}
