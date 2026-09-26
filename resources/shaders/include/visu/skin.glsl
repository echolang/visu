/**
 * The frame's joint palette at slot 2 and the four-influence blend. Mirrors
 * visu::graphics::SKIN_PALETTE_ROWS. Each joint is three rows: the rows of the top 3x4 of its
 * column-major skinning matrix. An instance's joints start at its palette base row.
 */
#ifndef VISU_SKIN_GLSL
#define VISU_SKIN_GLSL

layout(std140, set = 0, binding = 2) uniform SkinPalette {
    vec4 u_skin_rows[3072];
};

// blend the rows first, then build one matrix: 12 madds per influence instead of 16
mat4 skin_matrix(uvec4 joints, vec4 weights, float base)
{
    uint b = uint(base + 0.5);
    uvec4 at = uvec4(b) + joints * 3u;
    vec4 r0 = u_skin_rows[at.x] * weights.x
        + u_skin_rows[at.y] * weights.y
        + u_skin_rows[at.z] * weights.z
        + u_skin_rows[at.w] * weights.w;
    vec4 r1 = u_skin_rows[at.x + 1u] * weights.x
        + u_skin_rows[at.y + 1u] * weights.y
        + u_skin_rows[at.z + 1u] * weights.z
        + u_skin_rows[at.w + 1u] * weights.w;
    vec4 r2 = u_skin_rows[at.x + 2u] * weights.x
        + u_skin_rows[at.y + 2u] * weights.y
        + u_skin_rows[at.z + 2u] * weights.z
        + u_skin_rows[at.w + 2u] * weights.w;
    return mat4(
        vec4(r0.x, r1.x, r2.x, 0.0),
        vec4(r0.y, r1.y, r2.y, 0.0),
        vec4(r0.z, r1.z, r2.z, 0.0),
        vec4(r0.w, r1.w, r2.w, 1.0)
    );
}

#endif
