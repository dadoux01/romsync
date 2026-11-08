/*
 * sha.h - SHA-1 (game identifiers of homebrew ROMs, "h:<sha1>") and
 * SHA-256 (save hashes, X-Content-SHA256), as in FIPS 180-4.
 *
 * Both work in streaming mode (init, update as many times as needed,
 * final), so that a large ROM can be hashed without loading it in memory.
 */
#ifndef RS_SHA_H
#define RS_SHA_H

#include <stddef.h>
#include <stdint.h>

typedef struct {
    uint32_t h[5];
    uint64_t total;      /* bytes hashed so far */
    uint8_t block[64];   /* pending bytes, less than one block */
    size_t used;
} rs_sha1;

typedef struct {
    uint32_t h[8];
    uint64_t total;
    uint8_t block[64];
    size_t used;
} rs_sha256;

void rs_sha1_init(rs_sha1 *c);
void rs_sha1_update(rs_sha1 *c, const void *data, size_t len);
void rs_sha1_final(rs_sha1 *c, uint8_t out[20]);

void rs_sha256_init(rs_sha256 *c);
void rs_sha256_update(rs_sha256 *c, const void *data, size_t len);
void rs_sha256_final(rs_sha256 *c, uint8_t out[32]);

/* One-shot helpers writing lowercase hex (41 and 65 bytes with the NUL). */
void rs_sha1_hex(const void *data, size_t len, char out[41]);
void rs_sha256_hex(const void *data, size_t len, char out[65]);

#endif
