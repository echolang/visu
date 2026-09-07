#ifndef VISU_VG_FONT_H
#define VISU_VG_FONT_H

#include <stdint.h>

typedef struct VgFont VgFont;

typedef struct VgFontLayout
{
    int32_t ascent;
    int32_t descent;
    int32_t lineGap;
    int32_t unitsPerEm;
    int32_t glyphCount;
    int32_t kernPairCount;
    int32_t class1Count;
    int32_t class2Count;
    int32_t hasClassKern;
    int32_t hiCount;
} VgFontLayout;

VgFont *vg_font_load(const uint8_t *ttf, int32_t bytes);
void vg_font_free(VgFont *font);
void vg_font_layout(VgFont *font, VgFontLayout *out);
int vg_font_copy_cmap(VgFont *font, int32_t *out, int32_t cap);
int vg_font_copy_advance(VgFont *font, int32_t *out, int32_t cap);
int vg_font_copy_kern(VgFont *font, uint64_t *keys, int32_t *vals, int32_t cap);
int vg_font_copy_class1(VgFont *font, int32_t *out, int32_t cap);
int vg_font_copy_class2(VgFont *font, int32_t *out, int32_t cap);
int vg_font_copy_class_matrix(VgFont *font, int32_t *out, int32_t cap);
int vg_font_copy_cmap_hi(VgFont *font, int32_t *starts, int32_t *ends, int32_t *glyphs, int32_t cap);
void vg_font_drop_layout(VgFont *font);
int vg_font_glyph(
    VgFont *font,
    int32_t glyph,
    float size,
    int32_t *w,
    int32_t *h,
    int32_t *xoff,
    int32_t *yoff);
int vg_font_raster(
    VgFont *font,
    int32_t glyph,
    float size,
    uint8_t *out,
    int32_t stride);

#endif
