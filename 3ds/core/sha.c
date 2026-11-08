/*
 * sha.c - SHA-1 and SHA-256 (FIPS 180-4).
 *
 * Both hashes cut the input into 64-byte blocks and mix each block into a
 * small state (5 or 8 32-bit words). The last block is padded with 0x80,
 * zeros and the message length in bits (big-endian).
 */
#include "sha.h"

#include <string.h>

#include "rs.h"

#define ROL(x, n) (((x) << (n)) | ((x) >> (32 - (n))))
#define ROR(x, n) (((x) >> (n)) | ((x) << (32 - (n))))

static uint32_t load_be32(const uint8_t *p)
{
    return (uint32_t)p[0] << 24 | (uint32_t)p[1] << 16 | (uint32_t)p[2] << 8 | p[3];
}

static void store_be32(uint8_t *p, uint32_t v)
{
    p[0] = (uint8_t)(v >> 24);
    p[1] = (uint8_t)(v >> 16);
    p[2] = (uint8_t)(v >> 8);
    p[3] = (uint8_t)v;
}

/* Feeds len bytes to a 64-byte block buffer and calls compress() on each
 * full block. Shared by both hashes. */
#define FEED(c, data, len, compress)                                   \
    do {                                                               \
        const uint8_t *in_ = (const uint8_t *)(data);                  \
        size_t n_ = (len);                                             \
        (c)->total += n_;                                              \
        while (n_ > 0) {                                               \
            size_t take_ = 64 - (c)->used;                             \
            if (take_ > n_)                                            \
                take_ = n_;                                            \
            memcpy((c)->block + (c)->used, in_, take_);                \
            (c)->used += take_;                                        \
            in_ += take_;                                              \
            n_ -= take_;                                               \
            if ((c)->used == 64) {                                     \
                compress((c)->h, (c)->block);                          \
                (c)->used = 0;                                         \
            }                                                          \
        }                                                              \
    } while (0)

/* Pads the last block: 0x80, zeros, then the length in bits. */
#define PAD(c, compress)                                               \
    do {                                                               \
        uint64_t bits_ = (c)->total * 8;                               \
        (c)->block[(c)->used++] = 0x80;                                \
        if ((c)->used > 56) {                                          \
            memset((c)->block + (c)->used, 0, 64 - (c)->used);         \
            compress((c)->h, (c)->block);                              \
            (c)->used = 0;                                             \
        }                                                              \
        memset((c)->block + (c)->used, 0, 56 - (c)->used);             \
        for (int i_ = 0; i_ < 8; i_++)                                 \
            (c)->block[56 + i_] = (uint8_t)(bits_ >> (56 - 8 * i_));   \
        compress((c)->h, (c)->block);                                  \
    } while (0)

/* ---- SHA-1 ------------------------------------------------------------- */

static void sha1_compress(uint32_t h[5], const uint8_t block[64])
{
    uint32_t w[80];
    for (int i = 0; i < 16; i++)
        w[i] = load_be32(block + 4 * i);
    for (int i = 16; i < 80; i++)
        w[i] = ROL(w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16], 1);

    uint32_t a = h[0], b = h[1], c = h[2], d = h[3], e = h[4];
    for (int i = 0; i < 80; i++) {
        uint32_t f, k;
        if (i < 20) {
            f = (b & c) | (~b & d);
            k = 0x5A827999;
        } else if (i < 40) {
            f = b ^ c ^ d;
            k = 0x6ED9EBA1;
        } else if (i < 60) {
            f = (b & c) | (b & d) | (c & d);
            k = 0x8F1BBCDC;
        } else {
            f = b ^ c ^ d;
            k = 0xCA62C1D6;
        }
        uint32_t t = ROL(a, 5) + f + e + k + w[i];
        e = d;
        d = c;
        c = ROL(b, 30);
        b = a;
        a = t;
    }
    h[0] += a;
    h[1] += b;
    h[2] += c;
    h[3] += d;
    h[4] += e;
}

void rs_sha1_init(rs_sha1 *c)
{
    static const uint32_t iv[5] = {0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476, 0xC3D2E1F0};
    memcpy(c->h, iv, sizeof iv);
    c->total = 0;
    c->used = 0;
}

void rs_sha1_update(rs_sha1 *c, const void *data, size_t len)
{
    FEED(c, data, len, sha1_compress);
}

void rs_sha1_final(rs_sha1 *c, uint8_t out[20])
{
    PAD(c, sha1_compress);
    for (int i = 0; i < 5; i++)
        store_be32(out + 4 * i, c->h[i]);
}

/* ---- SHA-256 ----------------------------------------------------------- */

static const uint32_t K256[64] = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
};

static void sha256_compress(uint32_t h[8], const uint8_t block[64])
{
    uint32_t w[64];
    for (int i = 0; i < 16; i++)
        w[i] = load_be32(block + 4 * i);
    for (int i = 16; i < 64; i++) {
        uint32_t s0 = ROR(w[i - 15], 7) ^ ROR(w[i - 15], 18) ^ (w[i - 15] >> 3);
        uint32_t s1 = ROR(w[i - 2], 17) ^ ROR(w[i - 2], 19) ^ (w[i - 2] >> 10);
        w[i] = w[i - 16] + s0 + w[i - 7] + s1;
    }

    uint32_t a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7];
    for (int i = 0; i < 64; i++) {
        uint32_t s1 = ROR(e, 6) ^ ROR(e, 11) ^ ROR(e, 25);
        uint32_t ch = (e & f) ^ (~e & g);
        uint32_t t1 = hh + s1 + ch + K256[i] + w[i];
        uint32_t s0 = ROR(a, 2) ^ ROR(a, 13) ^ ROR(a, 22);
        uint32_t maj = (a & b) ^ (a & c) ^ (b & c);
        uint32_t t2 = s0 + maj;
        hh = g;
        g = f;
        f = e;
        e = d + t1;
        d = c;
        c = b;
        b = a;
        a = t1 + t2;
    }
    h[0] += a;
    h[1] += b;
    h[2] += c;
    h[3] += d;
    h[4] += e;
    h[5] += f;
    h[6] += g;
    h[7] += hh;
}

void rs_sha256_init(rs_sha256 *c)
{
    static const uint32_t iv[8] = {0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
                                   0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19};
    memcpy(c->h, iv, sizeof iv);
    c->total = 0;
    c->used = 0;
}

void rs_sha256_update(rs_sha256 *c, const void *data, size_t len)
{
    FEED(c, data, len, sha256_compress);
}

void rs_sha256_final(rs_sha256 *c, uint8_t out[32])
{
    PAD(c, sha256_compress);
    for (int i = 0; i < 8; i++)
        store_be32(out + 4 * i, c->h[i]);
}

/* ---- One-shot helpers -------------------------------------------------- */

void rs_sha1_hex(const void *data, size_t len, char out[41])
{
    rs_sha1 c;
    uint8_t d[20];
    rs_sha1_init(&c);
    rs_sha1_update(&c, data, len);
    rs_sha1_final(&c, d);
    rs_hex(d, sizeof d, out);
}

void rs_sha256_hex(const void *data, size_t len, char out[65])
{
    rs_sha256 c;
    uint8_t d[32];
    rs_sha256_init(&c);
    rs_sha256_update(&c, data, len);
    rs_sha256_final(&c, d);
    rs_hex(d, sizeof d, out);
}
