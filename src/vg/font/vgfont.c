#include "vgfont.h"

#include <stdlib.h>
#include <string.h>

#define STB_TRUETYPE_IMPLEMENTATION
#define STBTT_STATIC
#include "stb_truetype.h"

#define VG_CMAP 65536

struct VgFont {
    stbtt_fontinfo info;
    const uint8_t *ttf;
    int32_t bytes;
    int32_t ascent;
    int32_t descent;
    int32_t lineGap;
    int32_t unitsPerEm;
    int32_t glyphCount;
    int32_t *cmap;
    int32_t *advance;
    uint64_t *kernKeys;
    int32_t *kernVals;
    int32_t kernCount;
    int32_t kernCap;
    int32_t *class1;
    int32_t *class2;
    int32_t *classMatrix;
    int32_t class1Count;
    int32_t class2Count;
    int32_t hasClassKern;
    int32_t *hiStart;
    int32_t *hiEnd;
    int32_t *hiGlyph;
    int32_t hiCount;
    int32_t hiCap;
};

static void layout_free(VgFont *font);
static int extract_layout(VgFont *font);
static int pairs_push(VgFont *font, uint64_t key, int32_t adv);
static int hi_push(VgFont *font, int32_t start, int32_t end, int32_t glyph);
static int coverage_glyph_at(stbtt_uint8 *coverage, int index);
static void dump_pairpos(VgFont *font, stbtt_uint8 *table);
static void dump_gpos(VgFont *font);
static void dump_kern_table(VgFont *font);
static void dump_cmap_hi(VgFont *font);

static uint64_t pair_key(int32_t g1, int32_t g2)
{
    return ((uint64_t)(uint32_t)g1 << 32) | (uint32_t)g2;
}

static void layout_free(VgFont *font)
{
    free(font->cmap);
    free(font->advance);
    free(font->kernKeys);
    free(font->kernVals);
    free(font->class1);
    free(font->class2);
    free(font->classMatrix);
    free(font->hiStart);
    free(font->hiEnd);
    free(font->hiGlyph);
    font->cmap = NULL;
    font->advance = NULL;
    font->kernKeys = NULL;
    font->kernVals = NULL;
    font->class1 = NULL;
    font->class2 = NULL;
    font->classMatrix = NULL;
    font->hiStart = NULL;
    font->hiEnd = NULL;
    font->hiGlyph = NULL;
    font->kernCount = 0;
    font->kernCap = 0;
    font->class1Count = 0;
    font->class2Count = 0;
    font->hasClassKern = 0;
    font->hiCount = 0;
    font->hiCap = 0;
}

static int pairs_push(VgFont *font, uint64_t key, int32_t adv)
{
    if (font->kernCount >= font->kernCap) {
        int32_t cap = font->kernCap == 0 ? 64 : font->kernCap * 2;
        uint64_t *keys = (uint64_t *)realloc(font->kernKeys, (size_t)cap * sizeof(uint64_t));
        int32_t *vals = (int32_t *)realloc(font->kernVals, (size_t)cap * sizeof(int32_t));

        if (keys == NULL || vals == NULL) {
            free(keys == NULL ? font->kernKeys : keys);
            free(vals == NULL ? font->kernVals : vals);
            font->kernKeys = NULL;
            font->kernVals = NULL;
            font->kernCount = 0;
            font->kernCap = 0;
            return 0;
        }

        font->kernKeys = keys;
        font->kernVals = vals;
        font->kernCap = cap;
    }

    font->kernKeys[font->kernCount] = key;
    font->kernVals[font->kernCount] = adv;
    font->kernCount = font->kernCount + 1;
    return 1;
}

static int hi_push(VgFont *font, int32_t start, int32_t end, int32_t glyph)
{
    if (font->hiCount >= font->hiCap) {
        int32_t cap = font->hiCap == 0 ? 32 : font->hiCap * 2;
        int32_t *starts = (int32_t *)realloc(font->hiStart, (size_t)cap * sizeof(int32_t));
        int32_t *ends = (int32_t *)realloc(font->hiEnd, (size_t)cap * sizeof(int32_t));
        int32_t *gs = (int32_t *)realloc(font->hiGlyph, (size_t)cap * sizeof(int32_t));

        if (starts == NULL || ends == NULL || gs == NULL) {
            free(starts == NULL ? font->hiStart : starts);
            free(ends == NULL ? font->hiEnd : ends);
            free(gs == NULL ? font->hiGlyph : gs);
            font->hiStart = NULL;
            font->hiEnd = NULL;
            font->hiGlyph = NULL;
            font->hiCount = 0;
            font->hiCap = 0;
            return 0;
        }

        font->hiStart = starts;
        font->hiEnd = ends;
        font->hiGlyph = gs;
        font->hiCap = cap;
    }

    font->hiStart[font->hiCount] = start;
    font->hiEnd[font->hiCount] = end;
    font->hiGlyph[font->hiCount] = glyph;
    font->hiCount = font->hiCount + 1;
    return 1;
}

static int coverage_glyph_at(stbtt_uint8 *coverage, int index)
{
    int format = ttUSHORT(coverage);

    if (index < 0) {
        return -1;
    }

    if (format == 1) {
        int count = ttUSHORT(coverage + 2);

        if (index >= count) {
            return -1;
        }

        return ttUSHORT(coverage + 4 + 2 * index);
    }

    if (format == 2) {
        int rangeCount = ttUSHORT(coverage + 2);
        int i = 0;
        int seen = 0;

        while (i < rangeCount) {
            stbtt_uint8 *rec = coverage + 4 + 6 * i;
            int start = ttUSHORT(rec);
            int end = ttUSHORT(rec + 2);
            int n = end - start + 1;

            if (index < seen + n) {
                return start + (index - seen);
            }

            seen = seen + n;
            i = i + 1;
        }
    }

    return -1;
}

static void dump_pairpos(VgFont *font, stbtt_uint8 *table)
{
    int posFormat = ttUSHORT(table);
    int coverageOffset = ttUSHORT(table + 2);
    int vf1 = ttUSHORT(table + 4);
    int vf2 = ttUSHORT(table + 6);

    if (vf1 != 4 || vf2 != 0) {
        return;
    }

    if (posFormat == 1) {
        int pairSetCount = ttUSHORT(table + 8);
        int i = 0;

        while (i < pairSetCount) {
            int g1 = coverage_glyph_at(table + coverageOffset, i);
            int pairPosOffset = ttUSHORT(table + 10 + 2 * i);
            stbtt_uint8 *pairValueTable = table + pairPosOffset;
            int pairValueCount = ttUSHORT(pairValueTable);
            int k = 0;

            if (g1 >= 0) {
                while (k < pairValueCount) {
                    stbtt_uint8 *rec = pairValueTable + 2 + 4 * k;
                    int g2 = ttUSHORT(rec);
                    int adv = ttSHORT(rec + 2);
                    pairs_push(font, pair_key(g1, g2), adv);
                    k = k + 1;
                }
            }

            i = i + 1;
        }

        return;
    }

    if (posFormat != 2 || font->hasClassKern) {
        return;
    }

    int classDef1Offset = ttUSHORT(table + 8);
    int classDef2Offset = ttUSHORT(table + 10);
    int class1Count = ttUSHORT(table + 12);
    int class2Count = ttUSHORT(table + 14);
    int glyphCount = font->glyphCount;
    int matrixCount = class1Count * class2Count;
    int g = 0;
    int i = 0;
    int32_t *class1 = NULL;
    int32_t *class2 = NULL;
    int32_t *matrix = NULL;

    if (class1Count <= 0 || class2Count <= 0 || glyphCount <= 0) {
        return;
    }

    class1 = (int32_t *)malloc((size_t)glyphCount * sizeof(int32_t));
    class2 = (int32_t *)malloc((size_t)glyphCount * sizeof(int32_t));
    matrix = (int32_t *)malloc((size_t)matrixCount * sizeof(int32_t));

    if (class1 == NULL || class2 == NULL || matrix == NULL) {
        free(class1);
        free(class2);
        free(matrix);
        return;
    }

    while (g < glyphCount) {
        int cov = stbtt__GetCoverageIndex(table + coverageOffset, g);
        int c1 = stbtt__GetGlyphClass(table + classDef1Offset, g);
        int c2 = stbtt__GetGlyphClass(table + classDef2Offset, g);

        if (cov < 0) {
            class1[g] = -1;
        } else if (c1 < 0 || c1 >= class1Count) {
            class1[g] = -1;
        } else {
            class1[g] = c1;
        }

        if (c2 < 0 || c2 >= class2Count) {
            class2[g] = 0;
        } else {
            class2[g] = c2;
        }

        g = g + 1;
    }

    while (i < matrixCount) {
        matrix[i] = ttSHORT(table + 16 + 2 * i);
        i = i + 1;
    }

    font->class1 = class1;
    font->class2 = class2;
    font->classMatrix = matrix;
    font->class1Count = class1Count;
    font->class2Count = class2Count;
    font->hasClassKern = 1;
}

static void dump_gpos(VgFont *font)
{
    stbtt_fontinfo *info = &font->info;
    stbtt_uint8 *data = NULL;
    stbtt_uint8 *lookupList = NULL;
    int lookupCount = 0;
    int i = 0;

    if (!info->gpos) {
        return;
    }

    data = info->data + info->gpos;

    // lookup list stays at offset 8 for gpos 1.x
    if (ttUSHORT(data + 0) != 1) {
        return;
    }

    lookupList = data + ttUSHORT(data + 8);
    lookupCount = ttUSHORT(lookupList);

    while (i < lookupCount) {
        stbtt_uint8 *lookupTable = lookupList + ttUSHORT(lookupList + 2 + 2 * i);
        int lookupType = ttUSHORT(lookupTable);
        int subTableCount = ttUSHORT(lookupTable + 4);
        stbtt_uint8 *subTableOffsets = lookupTable + 6;
        int sti = 0;

        while (sti < subTableCount) {
            stbtt_uint8 *table = lookupTable + ttUSHORT(subTableOffsets + 2 * sti);
            int type = lookupType;

            if (type == 9) {
                if (ttUSHORT(table) == 1) {
                    stbtt_uint32 ext = ttULONG(table + 4);
                    type = ttUSHORT(table + 2);
                    table = table + ext;
                } else {
                    type = 0;
                }
            }

            if (type == 2) {
                dump_pairpos(font, table);
            }

            sti = sti + 1;
        }

        i = i + 1;
    }
}

static void dump_kern_table(VgFont *font)
{
    stbtt_kerningentry *table = NULL;
    int n = 0;
    int i = 0;

    if (font->kernCount > 0 || font->hasClassKern || !font->info.kern) {
        return;
    }

    n = stbtt_GetKerningTableLength(&font->info);

    if (n <= 0) {
        return;
    }

    table = (stbtt_kerningentry *)malloc((size_t)n * sizeof(stbtt_kerningentry));

    if (table == NULL) {
        return;
    }

    n = stbtt_GetKerningTable(&font->info, table, n);
    i = 0;

    while (i < n) {
        pairs_push(font, pair_key(table[i].glyph1, table[i].glyph2), table[i].advance);
        i = i + 1;
    }

    free(table);
}

static void dump_cmap_hi(VgFont *font)
{
    stbtt_uint8 *data = font->info.data;
    stbtt_uint32 fontstart = (stbtt_uint32)font->info.fontstart;
    stbtt_uint32 cmap = stbtt__find_table(data, fontstart, "cmap");
    int num = 0;
    int i = 0;

    if (!cmap) {
        return;
    }

    num = ttUSHORT(data + cmap + 2);

    while (i < num) {
        stbtt_uint32 off = ttULONG(data + cmap + 4 + 8 * i + 4);
        int fmt = ttUSHORT(data + cmap + off);
        uint32_t groups = 0;
        uint32_t g = 0;

        if (fmt != 12) {
            i = i + 1;
            continue;
        }

        groups = ttULONG(data + cmap + off + 12);

        if (groups > 65536u) {
            groups = 65536u;
        }

        while (g < groups) {
            stbtt_uint8 *rec = data + cmap + off + 16 + 12 * g;
            uint32_t start = ttULONG(rec);
            uint32_t end = ttULONG(rec + 4);
            uint32_t startGlyph = ttULONG(rec + 8);

            g = g + 1;

            if (end < start || end <= 65535u || start > 0x10FFFFu) {
                continue;
            }

            if (end > 0x10FFFFu) {
                end = 0x10FFFFu;
            }

            if (start <= 65535u) {
                startGlyph = startGlyph + (65536u - start);
                start = 65536u;
            }

            if (!hi_push(font, (int32_t)start, (int32_t)end, (int32_t)startGlyph)) {
                return;
            }
        }

        return;
    }
}

static int extract_layout(VgFont *font)
{
    int a = 0;
    int d = 0;
    int g = 0;
    int i = 0;
    int32_t n = 0;

    stbtt_GetFontVMetrics(&font->info, &a, &d, &g);
    font->ascent = a;
    font->descent = d;
    font->lineGap = g;
    font->unitsPerEm = (int32_t)ttUSHORT(font->info.data + font->info.head + 18);
    font->glyphCount = font->info.numGlyphs;
    n = font->glyphCount;

    font->cmap = (int32_t *)calloc((size_t)VG_CMAP, sizeof(int32_t));

    if (font->cmap == NULL) {
        return 0;
    }

    i = 0;

    while (i < VG_CMAP) {
        font->cmap[i] = stbtt_FindGlyphIndex(&font->info, i);
        i = i + 1;
    }

    if (n > 0) {
        font->advance = (int32_t *)malloc((size_t)n * sizeof(int32_t));

        if (font->advance == NULL) {
            return 0;
        }

        i = 0;

        while (i < n) {
            int adv = 0;
            int lsb = 0;
            stbtt_GetGlyphHMetrics(&font->info, i, &adv, &lsb);
            font->advance[i] = adv;
            i = i + 1;
        }
    }

    dump_gpos(font);
    dump_kern_table(font);
    dump_cmap_hi(font);
    return 1;
}

VgFont *vg_font_load(const uint8_t *ttf, int32_t bytes)
{
    if (ttf == NULL || bytes < 4) {
        return NULL;
    }

    int offset = stbtt_GetFontOffsetForIndex(ttf, 0);

    if (offset < 0) {
        return NULL;
    }

    VgFont *font = (VgFont *)calloc(1, sizeof(VgFont));

    if (font == NULL) {
        return NULL;
    }

    font->ttf = ttf;
    font->bytes = bytes;

    if (!stbtt_InitFont(&font->info, ttf, offset)) {
        free(font);
        return NULL;
    }

    if (!extract_layout(font)) {
        layout_free(font);
        free(font);
        return NULL;
    }

    return font;
}

void vg_font_free(VgFont *font)
{
    if (font == NULL) {
        return;
    }

    layout_free(font);
    free(font);
}

void vg_font_layout(VgFont *font, VgFontLayout *out)
{
    if (out == NULL) {
        return;
    }

    memset(out, 0, sizeof(*out));

    if (font == NULL) {
        return;
    }

    out->ascent = font->ascent;
    out->descent = font->descent;
    out->lineGap = font->lineGap;
    out->unitsPerEm = font->unitsPerEm;
    out->glyphCount = font->glyphCount;
    out->kernPairCount = font->kernCount;
    out->class1Count = font->class1Count;
    out->class2Count = font->class2Count;
    out->hasClassKern = font->hasClassKern;
    out->hiCount = font->hiCount;
}

static int copy_i32(const int32_t *src, int32_t n, int32_t *out, int32_t cap)
{
    if (out == NULL || n < 0) {
        return 0;
    }

    if (n > cap) {
        n = cap;
    }

    if (n > 0 && src != NULL) {
        memcpy(out, src, (size_t)n * sizeof(int32_t));
    }

    return n;
}

int vg_font_copy_cmap(VgFont *font, int32_t *out, int32_t cap)
{
    if (font == NULL) {
        return 0;
    }

    return copy_i32(font->cmap, VG_CMAP, out, cap);
}

int vg_font_copy_advance(VgFont *font, int32_t *out, int32_t cap)
{
    if (font == NULL) {
        return 0;
    }

    return copy_i32(font->advance, font->glyphCount, out, cap);
}

int vg_font_copy_kern(VgFont *font, uint64_t *keys, int32_t *vals, int32_t cap)
{
    int32_t n = 0;

    if (font == NULL || keys == NULL || vals == NULL) {
        return 0;
    }

    n = font->kernCount;

    if (n > cap) {
        n = cap;
    }

    if (n > 0) {
        memcpy(keys, font->kernKeys, (size_t)n * sizeof(uint64_t));
        memcpy(vals, font->kernVals, (size_t)n * sizeof(int32_t));
    }

    return n;
}

int vg_font_copy_class1(VgFont *font, int32_t *out, int32_t cap)
{
    if (font == NULL || !font->hasClassKern) {
        return 0;
    }

    return copy_i32(font->class1, font->glyphCount, out, cap);
}

int vg_font_copy_class2(VgFont *font, int32_t *out, int32_t cap)
{
    if (font == NULL || !font->hasClassKern) {
        return 0;
    }

    return copy_i32(font->class2, font->glyphCount, out, cap);
}

int vg_font_copy_class_matrix(VgFont *font, int32_t *out, int32_t cap)
{
    int32_t n = 0;

    if (font == NULL || !font->hasClassKern) {
        return 0;
    }

    n = font->class1Count * font->class2Count;
    return copy_i32(font->classMatrix, n, out, cap);
}

int vg_font_copy_cmap_hi(VgFont *font, int32_t *starts, int32_t *ends, int32_t *glyphs, int32_t cap)
{
    int32_t n = 0;

    if (font == NULL || starts == NULL || ends == NULL || glyphs == NULL) {
        return 0;
    }

    n = font->hiCount;

    if (n > cap) {
        n = cap;
    }

    if (n > 0) {
        memcpy(starts, font->hiStart, (size_t)n * sizeof(int32_t));
        memcpy(ends, font->hiEnd, (size_t)n * sizeof(int32_t));
        memcpy(glyphs, font->hiGlyph, (size_t)n * sizeof(int32_t));
    }

    return n;
}

void vg_font_drop_layout(VgFont *font)
{
    if (font == NULL) {
        return;
    }

    layout_free(font);
}

int vg_font_glyph(
    VgFont *font,
    int32_t glyph,
    float size,
    int32_t *w,
    int32_t *h,
    int32_t *xoff,
    int32_t *yoff)
{
    if (font == NULL || size <= 0.0f) {
        return 0;
    }

    float scale = stbtt_ScaleForPixelHeight(&font->info, size);
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

    return 1;
}

int vg_font_raster(
    VgFont *font,
    int32_t glyph,
    float size,
    uint8_t *out,
    int32_t stride)
{
    if (font == NULL || out == NULL || size <= 0.0f || stride <= 0) {
        return 0;
    }

    float scale = stbtt_ScaleForPixelHeight(&font->info, size);
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
