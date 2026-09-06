#include "vgfont.h"

#include <stdlib.h>

#define STB_TRUETYPE_IMPLEMENTATION
#define STBTT_STATIC
#include "stb_truetype.h"

struct VgFont {
    stbtt_fontinfo info;
    const uint8_t *ttf;
    int32_t bytes;
};

VgFont *vg_font_load(const uint8_t *ttf, int32_t bytes)
{
    if (ttf == NULL || bytes < 4) {
        return NULL;
    }

    int offset = stbtt_GetFontOffsetForIndex(ttf, 0);

    if (offset < 0) {
        return NULL;
    }

    VgFont *font = (VgFont *)malloc(sizeof(VgFont));

    if (font == NULL) {
        return NULL;
    }

    font->ttf = ttf;
    font->bytes = bytes;

    if (!stbtt_InitFont(&font->info, ttf, offset)) {
        free(font);
        return NULL;
    }

    return font;
}

void vg_font_free(VgFont *font)
{
    if (font != NULL) {
        free(font);
    }
}

void vg_font_metrics(
    VgFont *font,
    float size,
    float *ascent,
    float *descent,
    float *lineh)
{
    if (font == NULL) {
        return;
    }

    int a = 0;
    int d = 0;
    int g = 0;
    stbtt_GetFontVMetrics(&font->info, &a, &d, &g);
    float scale = stbtt_ScaleForPixelHeight(&font->info, size);

    if (ascent != NULL) {
        *ascent = (float)a * scale;
    }

    if (descent != NULL) {
        *descent = (float)d * scale;
    }

    if (lineh != NULL) {
        *lineh = (float)(a - d + g) * scale;
    }
}

int vg_font_glyph(
    VgFont *font,
    int32_t cp,
    float size,
    int32_t *w,
    int32_t *h,
    int32_t *xoff,
    int32_t *yoff,
    float *advance)
{
    if (font == NULL || size <= 0.0f) {
        return 0;
    }

    float scale = stbtt_ScaleForPixelHeight(&font->info, size);
    int glyph = stbtt_FindGlyphIndex(&font->info, cp);
    int x0 = 0;
    int y0 = 0;
    int x1 = 0;
    int y1 = 0;
    stbtt_GetGlyphBitmapBox(&font->info, glyph, scale, scale, &x0, &y0, &x1, &y1);

    if (w != NULL) {
        *w = x1 - x0;
    }

    if (h != NULL) {
        *h = y1 - y0;
    }

    if (xoff != NULL) {
        *xoff = x0;
    }

    if (yoff != NULL) {
        *yoff = y0;
    }

    int adv = 0;
    int lsb = 0;
    stbtt_GetGlyphHMetrics(&font->info, glyph, &adv, &lsb);

    if (advance != NULL) {
        *advance = (float)adv * scale;
    }

    return 1;
}

int vg_font_raster(
    VgFont *font,
    int32_t cp,
    float size,
    uint8_t *out,
    int32_t stride)
{
    if (font == NULL || out == NULL || size <= 0.0f || stride <= 0) {
        return 0;
    }

    float scale = stbtt_ScaleForPixelHeight(&font->info, size);
    int glyph = stbtt_FindGlyphIndex(&font->info, cp);
    int x0 = 0;
    int y0 = 0;
    int x1 = 0;
    int y1 = 0;
    stbtt_GetGlyphBitmapBox(&font->info, glyph, scale, scale, &x0, &y0, &x1, &y1);
    int w = x1 - x0;
    int h = y1 - y0;

    if (w <= 0 || h <= 0) {
        return 0;
    }

    stbtt_MakeGlyphBitmap(&font->info, out, w, h, stride, scale, scale, glyph);
    return 1;
}

float vg_font_kern(VgFont *font, int32_t a, int32_t b, float size)
{
    if (font == NULL || size <= 0.0f) {
        return 0.0f;
    }

    float scale = stbtt_ScaleForPixelHeight(&font->info, size);
    return scale * (float)stbtt_GetCodepointKernAdvance(&font->info, a, b);
}
