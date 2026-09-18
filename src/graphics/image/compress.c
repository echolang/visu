#include "image.h"

#include <string.h>

static const int k_w4[16] = {
    0, 4, 9, 13, 17, 21, 26, 30, 34, 38, 43, 47, 51, 55, 60, 64
};

static void put_bits(uint8_t *block, int start, int n, uint32_t val)
{
    int i = 0;

    while (i < n) {
        if ((val & (1u << i)) != 0) {
            int b = start + i;
            block[b >> 3] = (uint8_t)(block[b >> 3] | (uint8_t)(1u << (b & 7)));
        }

        i = i + 1;
    }
}

static void sample_block(
    const uint8_t *rgba,
    int32_t w,
    int32_t h,
    int32_t x0,
    int32_t y0,
    uint8_t px[16][4]
)
{
    int i = 0;

    while (i < 16) {
        int32_t x = x0 + (i & 3);
        int32_t y = y0 + (i >> 2);
        if (x >= w) {
            x = w - 1;
        }
        if (y >= h) {
            y = h - 1;
        }
        if (x < 0) {
            x = 0;
        }
        if (y < 0) {
            y = 0;
        }

        const uint8_t *s = rgba + (((y * w) + x) * 4);
        px[i][0] = s[0];
        px[i][1] = s[1];
        px[i][2] = s[2];
        px[i][3] = s[3];
        i = i + 1;
    }
}

static int dist2(const uint8_t *a, const uint8_t *b)
{
    int dr = (int)a[0] - (int)b[0];
    int dg = (int)a[1] - (int)b[1];
    int db = (int)a[2] - (int)b[2];
    int da = (int)a[3] - (int)b[3];
    return (dr * dr) + (dg * dg) + (db * db) + (da * da);
}

static void lerp8(const uint8_t *e0, const uint8_t *e1, int w, uint8_t *out)
{
    int c = 0;

    while (c < 4) {
        int v = (((int)e0[c] * (64 - w)) + ((int)e1[c] * w) + 32) >> 6;
        if (v < 0) {
            v = 0;
        }
        if (v > 255) {
            v = 255;
        }

        out[c] = (uint8_t)v;
        c = c + 1;
    }
}

static void bc7_mode6(const uint8_t px[16][4], uint8_t out[16])
{
    int a = 0;
    int b = 0;
    int best = -1;
    int i = 0;

    while (i < 16) {
        int j = i + 1;

        while (j < 16) {
            int d = dist2(px[i], px[j]);
            if (d > best) {
                best = d;
                a = i;
                b = j;
            }

            j = j + 1;
        }

        i = i + 1;
    }

    uint8_t e0[4];
    uint8_t e1[4];
    e0[0] = px[a][0];
    e0[1] = px[a][1];
    e0[2] = px[a][2];
    e0[3] = px[a][3];
    e1[0] = px[b][0];
    e1[1] = px[b][1];
    e1[2] = px[b][2];
    e1[3] = px[b][3];

    int idx[16];
    i = 0;

    while (i < 16) {
        int pick = 0;
        int err = 1 << 30;
        int t = 0;

        while (t < 16) {
            uint8_t g[4];
            lerp8(e0, e1, k_w4[t], g);
            int e = dist2(px[i], g);
            if (e < err) {
                err = e;
                pick = t;
            }

            t = t + 1;
        }

        idx[i] = pick;
        i = i + 1;
    }

    if (idx[0] >= 8) {
        uint8_t s0 = e0[0];
        uint8_t s1 = e0[1];
        uint8_t s2 = e0[2];
        uint8_t s3 = e0[3];
        e0[0] = e1[0];
        e0[1] = e1[1];
        e0[2] = e1[2];
        e0[3] = e1[3];
        e1[0] = s0;
        e1[1] = s1;
        e1[2] = s2;
        e1[3] = s3;
        i = 0;

        while (i < 16) {
            idx[i] = 15 - idx[i];
            i = i + 1;
        }
    }

    memset(out, 0, 16);
    put_bits(out, 0, 7, 0x40);

    int c = 0;

    while (c < 4) {
        uint32_t v0 = ((uint32_t)e0[c] >> 1) & 127u;
        uint32_t v1 = ((uint32_t)e1[c] >> 1) & 127u;
        put_bits(out, 7 + (c * 14), 7, v0);
        put_bits(out, 14 + (c * 14), 7, v1);
        c = c + 1;
    }

    put_bits(out, 63, 1, (uint32_t)e0[0] & 1u);
    put_bits(out, 64, 1, (uint32_t)e1[0] & 1u);
    put_bits(out, 65, 3, (uint32_t)idx[0] & 7u);

    i = 1;

    while (i < 16) {
        put_bits(out, 68 + ((i - 1) * 4), 4, (uint32_t)idx[i]);
        i = i + 1;
    }
}

static void astc_void_extent(const uint8_t px[16][4], uint8_t out[16])
{
    int r = 0;
    int g = 0;
    int b = 0;
    int a = 0;
    int i = 0;

    while (i < 16) {
        r = r + (int)px[i][0];
        g = g + (int)px[i][1];
        b = b + (int)px[i][2];
        a = a + (int)px[i][3];
        i = i + 1;
    }

    memset(out, 0, 16);
    put_bits(out, 0, 9, 0x1FCu);
    put_bits(out, 9, 1, 0);
    put_bits(out, 10, 2, 3u);
    put_bits(out, 12, 13, 0x1FFFu);
    put_bits(out, 25, 13, 0x1FFFu);
    put_bits(out, 38, 13, 0x1FFFu);
    put_bits(out, 51, 13, 0x1FFFu);
    put_bits(out, 64, 16, ((uint32_t)(r / 16) << 8));
    put_bits(out, 80, 16, ((uint32_t)(g / 16) << 8));
    put_bits(out, 96, 16, ((uint32_t)(b / 16) << 8));
    put_bits(out, 112, 16, ((uint32_t)(a / 16) << 8));
}

static int32_t encode_blocks(
    const uint8_t *rgba,
    int32_t w,
    int32_t h,
    uint8_t *dst,
    int32_t dst_cap,
    int astc
)
{
    if (rgba == NULL || dst == NULL || w <= 0 || h <= 0) {
        return 0;
    }

    int32_t bw = (w + 3) / 4;
    int32_t bh = (h + 3) / 4;
    int32_t need = bw * bh * 16;
    if (need > dst_cap) {
        return 0;
    }

    int32_t y = 0;
    int32_t off = 0;

    while (y < h) {
        int32_t x = 0;

        while (x < w) {
            uint8_t px[16][4];
            sample_block(rgba, w, h, x, y, px);
            if (astc) {
                astc_void_extent(px, dst + off);
            } else {
                bc7_mode6(px, dst + off);
            }

            off = off + 16;
            x = x + 4;
        }

        y = y + 4;
    }

    return need;
}

int32_t visu_compress_bc7(
    const uint8_t *rgba,
    int32_t w,
    int32_t h,
    uint8_t *dst,
    int32_t dst_cap
)
{
    return encode_blocks(rgba, w, h, dst, dst_cap, 0);
}

int32_t visu_compress_astc4x4(
    const uint8_t *rgba,
    int32_t w,
    int32_t h,
    uint8_t *dst,
    int32_t dst_cap
)
{
    return encode_blocks(rgba, w, h, dst, dst_cap, 1);
}
