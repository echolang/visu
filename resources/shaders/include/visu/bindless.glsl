// visu::graphics::TextureTable: set 3, TEXTURE_TABLE_SAMPLERS samplers at binding 0 and
// TEXTURE_TABLE_CAPACITY textures from binding 16, indexed at run time. The samplers come first
// because a Metal argument buffer's ids climb by array size, and the binding is the id. The includer enables
// GL_EXT_nonuniform_qualifier (an extension line has to come before any declaration) and
// indexes through these, which wrap every index in nonuniformEXT: a draw that covers many
// materials reads a different texture per pixel.
#ifndef VISU_BINDLESS_GLSL
#define VISU_BINDLESS_GLSL

#define VISU_TEXTURE_TABLE_CAPACITY 4096
#define VISU_TEXTURE_TABLE_SAMPLERS 16

layout(set = 3, binding = 0) uniform sampler u_tableSamplers[VISU_TEXTURE_TABLE_SAMPLERS];
layout(set = 3, binding = 16) uniform texture2D u_tableTextures[VISU_TEXTURE_TABLE_CAPACITY];

vec4 table_sample(uint tex, uint samp, vec2 uv)
{
    return texture(sampler2D(u_tableTextures[nonuniformEXT(tex)], u_tableSamplers[nonuniformEXT(samp)]), uv);
}

vec4 table_sample_grad(uint tex, uint samp, vec2 uv, vec2 dx, vec2 dy)
{
    return textureGrad(sampler2D(u_tableTextures[nonuniformEXT(tex)], u_tableSamplers[nonuniformEXT(samp)]), uv, dx, dy);
}

vec4 table_sample_lod(uint tex, uint samp, vec2 uv, float lod)
{
    return textureLod(sampler2D(u_tableTextures[nonuniformEXT(tex)], u_tableSamplers[nonuniformEXT(samp)]), uv, lod);
}

#endif
