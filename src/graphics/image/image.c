#include "image.h"

#define STB_IMAGE_STATIC
#define STB_IMAGE_IMPLEMENTATION
#define STBI_ONLY_PNG
#define STBI_ONLY_HDR
#include "stb_image.h"

#define STB_IMAGE_WRITE_STATIC
#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "stb_image_write.h"

int visu_png_write(const char *path, int32_t w, int32_t h, const uint8_t *rgba)
{
    if (path == NULL || rgba == NULL || w <= 0 || h <= 0) {
        return 0;
    }

    return stbi_write_png(path, (int)w, (int)h, 4, rgba, (int)(w * 4));
}

int visu_png_load(const char *path, int32_t *w, int32_t *h, uint8_t **out)
{
    if (path == NULL || w == NULL || h == NULL || out == NULL) {
        return 0;
    }

    int iw = 0;
    int ih = 0;
    int n = 0;
    unsigned char *data = stbi_load(path, &iw, &ih, &n, 4);

    if (data == NULL) {
        *out = NULL;
        return 0;
    }

    *w = (int32_t)iw;
    *h = (int32_t)ih;
    *out = data;
    return 1;
}

void visu_png_free(uint8_t *p)
{
    stbi_image_free(p);
}

/* stbi_loadf keeps radiance values linear; only stbi_load applies the
 * HDR-to-LDR gamma, so this is the raw scene referred data. */
int visu_hdr_load(const char *path, int32_t *w, int32_t *h, float **out)
{
    if (path == NULL || w == NULL || h == NULL || out == NULL) {
        return 0;
    }

    int iw = 0;
    int ih = 0;
    int n = 0;
    float *data = stbi_loadf(path, &iw, &ih, &n, 4);

    if (data == NULL) {
        *out = NULL;
        return 0;
    }

    *w = (int32_t)iw;
    *h = (int32_t)ih;
    *out = data;
    return 1;
}

int visu_hdr_write(const char *path, int32_t w, int32_t h, const float *rgba)
{
    if (path == NULL || rgba == NULL || w <= 0 || h <= 0) {
        return 0;
    }

    return stbi_write_hdr(path, (int)w, (int)h, 4, rgba);
}

void visu_hdr_free(float *p)
{
    stbi_image_free(p);
}
