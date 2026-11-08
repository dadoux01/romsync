/* test_hash.c - SHA-1 and SHA-256 against the FIPS 180 test vectors. */
#include <stdlib.h>
#include <string.h>

#include "../core/rs.h"
#include "../core/sha.h"
#include "suites.h"
#include "test.h"

static void sha1_vectors(void)
{
    char hex[41];
    rs_sha1_hex("", 0, hex);
    CHECK_STR(hex, "da39a3ee5e6b4b0d3255bfef95601890afd80709");
    rs_sha1_hex("abc", 3, hex);
    CHECK_STR(hex, "a9993e364706816aba3e25717850c26c9cd0d89d");
    const char *two = "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq";
    rs_sha1_hex(two, strlen(two), hex);
    CHECK_STR(hex, "84983e441c3bd26ebaae4aa1f95129e5e54670f1");
}

static void sha256_vectors(void)
{
    char hex[65];
    rs_sha256_hex("", 0, hex);
    CHECK_STR(hex, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
    rs_sha256_hex("abc", 3, hex);
    CHECK_STR(hex, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
    const char *two = "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq";
    rs_sha256_hex(two, strlen(two), hex);
    CHECK_STR(hex, "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1");
}

/* One million 'a', fed in uneven pieces: exercises the block buffering. */
static void streaming_matches_one_shot(void)
{
    size_t n = 1000000;
    char *a = malloc(n);
    memset(a, 'a', n);
    rs_sha256 c;
    uint8_t d[32];
    char hex[65];
    rs_sha256_init(&c);
    for (size_t off = 0, step = 1; off < n; off += step, step = step * 3 % 997 + 1)
        rs_sha256_update(&c, a + off, off + step > n ? n - off : step);
    rs_sha256_final(&c, d);
    rs_hex(d, 32, hex);
    CHECK_STR(hex, "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0");

    rs_sha1 c1;
    uint8_t d1[20];
    char hex1[41];
    rs_sha1_init(&c1);
    for (size_t off = 0; off < n; off += 777)
        rs_sha1_update(&c1, a + off, off + 777 > n ? n - off : 777);
    rs_sha1_final(&c1, d1);
    rs_hex(d1, 20, hex1);
    CHECK_STR(hex1, "34aa973cd4c4daa4f61eeb2bdbad27316534016f");
    free(a);
}

void run_hash_tests(void)
{
    RUN(sha1_vectors);
    RUN(sha256_vectors);
    RUN(streaming_matches_one_shot);
}
