/**
 * Virtual shadow maps for point lights: the page math every stage shares, so the request, the
 * raster and the lookup agree to the texel. Mirrors visu::graphics::ShadowAtlas.
 *
 * A light has six virtual faces of VSM_FACE texels (90 degree perspective, near VSM_NEAR, far
 * the light radius), each a pyramid of VSM_MIPS levels cut into VSM_PAGE texel pages: 16 x 16
 * pages at mip 0 down to one at mip 4, 341 a face, 2046 a light. The page table holds one word
 * per virtual page: (generation << 16) | physical page, or VSM_NONE. A physical page is a cell of
 * VSM_CELL x VSM_CELL depths in the atlas buffer: VSM_PAGE texels plus a VSM_GUARD texel border
 * rendered with the same projection, so a 3 x 3 filter never leaves its cell. Dirty pages are
 * drawn into cells of a small scratch depth target (dirty page k in scratch cell k) and copied
 * into their physical cell, so no pass ever loads or stores the whole atlas.
 */
#ifndef VISU_VSM_GLSL
#define VISU_VSM_GLSL

#define VSM_FACE 1024.0
#define VSM_PAGE 64u
#define VSM_GUARD 1u
#define VSM_CELL 66u
#define VSM_PAGES 3844u
#define VSM_CELL_TEXELS 4356u
#define VSM_SCRATCH_ROW 16u
#define VSM_SCRATCH 1056u
#define VSM_MIPS 5u
#define VSM_FACE_PAGES 341u
#define VSM_LIGHT_PAGES 2046u
#define VSM_REQUEST_WORDS 64u
#define VSM_NEAR 0.05
#define VSM_NONE 0xFFFFFFFFu
#define VSM_GEN_MASK 0x7FFFu

// first page of each mip inside a face
uint vsm_mip_offset(uint mip)
{
    if (mip == 0u) {
        return 0u;
    }
    if (mip == 1u) {
        return 256u;
    }
    if (mip == 2u) {
        return 320u;
    }
    if (mip == 3u) {
        return 336u;
    }
    return 340u;
}

uint vsm_mip_side(uint mip)
{
    return 16u >> mip;
}

// forward, right and up of face 0..5 (+X -X +Y -Y +Z -Z)
void vsm_basis(uint face, out vec3 n, out vec3 r, out vec3 u)
{
    if (face == 0u) {
        n = vec3(1.0, 0.0, 0.0); r = vec3(0.0, 0.0, -1.0); u = vec3(0.0, 1.0, 0.0);
    } else if (face == 1u) {
        n = vec3(-1.0, 0.0, 0.0); r = vec3(0.0, 0.0, 1.0); u = vec3(0.0, 1.0, 0.0);
    } else if (face == 2u) {
        n = vec3(0.0, 1.0, 0.0); r = vec3(1.0, 0.0, 0.0); u = vec3(0.0, 0.0, -1.0);
    } else if (face == 3u) {
        n = vec3(0.0, -1.0, 0.0); r = vec3(1.0, 0.0, 0.0); u = vec3(0.0, 0.0, 1.0);
    } else if (face == 4u) {
        n = vec3(0.0, 0.0, 1.0); r = vec3(1.0, 0.0, 0.0); u = vec3(0.0, 1.0, 0.0);
    } else {
        n = vec3(0.0, 0.0, -1.0); r = vec3(-1.0, 0.0, 0.0); u = vec3(0.0, 1.0, 0.0);
    }
}

uint vsm_face(vec3 d)
{
    vec3 a = abs(d);
    if (a.x >= a.y && a.x >= a.z) {
        return d.x >= 0.0 ? 0u : 1u;
    }
    if (a.y >= a.z) {
        return d.y >= 0.0 ? 2u : 3u;
    }
    return d.z >= 0.0 ? 4u : 5u;
}

// the face-space view of `d` (world offset from the light): x, y, and the depth along forward
vec3 vsm_view(uint face, vec3 d)
{
    vec3 n;
    vec3 r;
    vec3 u;
    vsm_basis(face, n, r, u);
    return vec3(dot(d, r), dot(d, u), dot(d, n));
}

// zero-to-one perspective depth of a face-space depth `z`, far at the light radius
float vsm_depth(float z, float radius)
{
    float f = max(radius, VSM_NEAR * 2.0);
    float a = f / (f - VSM_NEAR);
    return a - a * VSM_NEAR / max(z, 1e-6);
}

// the clip-space z and w of face-space depth `z`
vec2 vsm_clip_zw(float z, float radius)
{
    float f = max(radius, VSM_NEAR * 2.0);
    float a = f / (f - VSM_NEAR);
    return vec2(a * z - a * VSM_NEAR, z);
}

// the world size of one screen pixel at view depth `viewDepth`, for a projection scale along y
// of `projectionY` over `height` pixels: the footprint the page level is picked from
float vsm_footprint(float viewDepth, float projectionY, float height)
{
    return 2.0 * viewDepth / (projectionY * height);
}

// the mip whose texel matches a world footprint `footprint` at face depth `z`
uint vsm_mip(float footprint, float z, float bias)
{
    float texel = 2.0 * max(z, VSM_NEAR) / VSM_FACE;
    float m = floor(log2(max(footprint / texel, 1.0)) + bias);
    return uint(clamp(m, 0.0, float(VSM_MIPS - 1u)));
}

// page (x, y) of face-space ndc `f` at `mip`
uvec2 vsm_page_xy(vec2 f, uint mip)
{
    uint side = vsm_mip_side(mip);
    vec2 uv = clamp(f * 0.5 + 0.5, 0.0, 0.99999);
    return min(uvec2(uv * float(side)), uvec2(side - 1u));
}

uint vsm_page_index(uint face, uint mip, uvec2 page)
{
    return face * VSM_FACE_PAGES + vsm_mip_offset(mip) + page.y * vsm_mip_side(mip) + page.x;
}

// face, mip and page back out of a page index inside one light
void vsm_page_of(uint index, out uint face, out uint mip, out uvec2 page)
{
    face = index / VSM_FACE_PAGES;
    uint rest = index % VSM_FACE_PAGES;
    mip = 0u;
    if (rest >= 340u) {
        mip = 4u;
    } else if (rest >= 336u) {
        mip = 3u;
    } else if (rest >= 320u) {
        mip = 2u;
    } else if (rest >= 256u) {
        mip = 1u;
    }
    uint local = rest - vsm_mip_offset(mip);
    uint side = vsm_mip_side(mip);
    page = uvec2(local % side, local / side);
}

// the face-ndc rect page `page` of `mip` covers, grown by the guard: xy min, zw max
vec4 vsm_page_rect(uint mip, uvec2 page)
{
    float side = float(vsm_mip_side(mip));
    float w = 2.0 / side;
    float g = w * float(VSM_GUARD) / float(VSM_PAGE);
    vec2 lo = vec2(page) * w - 1.0;
    return vec4(lo - g, lo + w + g);
}

// the scratch target's ndc rect of scratch cell `k`: xy min, zw max
vec4 vsm_scratch_rect(uint k)
{
    vec2 cell = vec2(float(k % VSM_SCRATCH_ROW), float(k / VSM_SCRATCH_ROW));
    vec2 lo = cell * float(VSM_CELL) / float(VSM_SCRATCH) * 2.0 - 1.0;
    return vec4(lo, lo + float(VSM_CELL) / float(VSM_SCRATCH) * 2.0);
}

// the cell texel (x right, y up) of face-space ndc `f` on the page `rect` holds, unclamped
vec2 vsm_cell_texel(vec2 f, vec4 rect)
{
    return (f - rect.xy) / (rect.zw - rect.xy) * float(VSM_CELL);
}

#endif
