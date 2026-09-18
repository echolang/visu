#ifndef VISU_IMAGE_H
#define VISU_IMAGE_H

#include <stdint.h>

int visu_png_write(const char *path, int32_t w, int32_t h, const uint8_t *rgba);
int visu_png_load(const char *path, int32_t *w, int32_t *h, uint8_t **out);
void visu_png_free(uint8_t *p);

int visu_hdr_load(const char *path, int32_t *w, int32_t *h, float **out);
int visu_hdr_write(const char *path, int32_t w, int32_t h, const float *rgba);
void visu_hdr_free(float *p);

int32_t visu_compress_bc7(
    const uint8_t *rgba,
    int32_t w,
    int32_t h,
    uint8_t *dst,
    int32_t dst_cap
);
int32_t visu_compress_astc4x4(
    const uint8_t *rgba,
    int32_t w,
    int32_t h,
    uint8_t *dst,
    int32_t dst_cap
);

#endif
