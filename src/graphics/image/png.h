#ifndef VISU_PNG_H
#define VISU_PNG_H

#include <stdint.h>

int visu_png_write(const char *path, int32_t w, int32_t h, const uint8_t *rgba);
int visu_png_load(const char *path, int32_t *w, int32_t *h, uint8_t **out);
void visu_png_free(uint8_t *p);

#endif
