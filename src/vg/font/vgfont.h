#ifndef VISU_VG_FONT_H
#define VISU_VG_FONT_H

#include <stdint.h>

typedef struct VgFont VgFont;

VgFont *vg_font_load(const uint8_t *ttf, int32_t bytes);
void vg_font_free(VgFont *font);
void vg_font_metrics(
    VgFont *font,
    float size,
    float *ascent,
    float *descent,
    float *lineh);
int vg_font_glyph(
    VgFont *font,
    int32_t cp,
    float size,
    int32_t *w,
    int32_t *h,
    int32_t *xoff,
    int32_t *yoff,
    float *advance);
int vg_font_raster(
    VgFont *font,
    int32_t cp,
    float size,
    uint8_t *out,
    int32_t stride);
float vg_font_kern(VgFont *font, int32_t a, int32_t b, float size);

#endif
