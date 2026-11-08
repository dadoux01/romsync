/*
 * test_update.c - versions, release verification and compatibility, the
 * cases of romsync_core's release_test.dart.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../core/sha.h"
#include "../core/update.h"
#include "../vendor/monocypher/monocypher-ed25519.h"
#include "suites.h"
#include "test.h"

static void versions_order_no_downgrade_no_pre_release_no_dev_update(void)
{
    const char *order[] = {"0.4.0", "0.5.0-rc1", "0.5.0-rc2", "v0.5.0", "0.5.1", "0.10.0", "1.0.0"};
    for (int i = 0; i + 1 < 7; i++) {
        rs_release_version a, b;
        CHECK(rs_version_parse(order[i], &a) && rs_version_parse(order[i + 1], &b));
        CHECK_INT(rs_version_compare(&a, &b), -1);
        CHECK_INT(rs_version_compare(&b, &a), 1);
        CHECK_INT(rs_version_compare(&a, &a), 0);
    }
    rs_release_version v;
    CHECK(!rs_version_parse("1.02.0", &v));
    CHECK(!rs_version_parse("1.2", &v));
    CHECK(!rs_version_parse("1.2.3-", &v));
    CHECK(!rs_version_parse("dev", &v));
    CHECK(rs_is_update("0.5.1", "0.5.0"));
    CHECK(!rs_is_update("0.5.0", "0.5.0"));
    CHECK(!rs_is_update("0.4.0", "0.5.0"));     /* never a downgrade */
    CHECK(!rs_is_update("0.6.0-rc1", "0.5.0")); /* pre-releases are ignored */
    CHECK(!rs_is_update("0.5.0", "dev"));       /* a dev build never updates */
}

static void the_built_in_key_is_keys_release_ed25519_pub(void)
{
    rs_buf b = {0};
    CHECK_INT(rs_read_file(t_repo("keys/release-ed25519.pub"), &b, NULL), RS_OK);
    rs_buf_terminate(&b);
    char *key = (char *)b.data;
    key[strcspn(key, "\r\n")] = 0;
    CHECK_STR(key, RS_RELEASE_PUBLIC_KEY);
    uint8_t raw[32];
    CHECK_INT(rs_base64_decode(RS_RELEASE_PUBLIC_KEY, raw, sizeof raw), 32);
    rs_buf_free(&b);
}

static void base64_and_sums(void)
{
    uint8_t out[8];
    CHECK_INT(rs_base64_decode("aGVsbG8=", out, sizeof out), 5);
    CHECK(memcmp(out, "hello", 5) == 0);
    CHECK_INT(rs_base64_decode("aGVs bG8=\n", out, sizeof out), 5);
    CHECK_INT(rs_base64_decode("a$==", out, sizeof out), -1);
    CHECK_INT(rs_base64_decode("aGVsbG8gd29ybGQ=", out, 4), -1); /* too small */

    char h[65], line[200];
    snprintf(line, sizeof line, "%s  x.zip\n%s *y.cia\r\n", "0123456789abcdef0123456789abcdef0123456789abcdef0123456789ABCDEF",
             "aa00000000000000000000000000000000000000000000000000000000000000");
    CHECK(rs_sum_for(line, strlen(line), "x.zip", h));
    CHECK_STR(h, "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef");
    CHECK(rs_sum_for(line, strlen(line), "y.cia", h));
    CHECK(!rs_sum_for(line, strlen(line), "z.zip", h));
    CHECK(!rs_sum_for(line, strlen(line), "x.zi", h));
}

/* Base64 of n bytes. */
static void b64(const uint8_t *in, size_t n, char *out)
{
    static const char a[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    size_t k = 0;
    for (size_t i = 0; i < n; i += 3) {
        uint32_t v = (uint32_t)in[i] << 16 | (i + 1 < n ? (uint32_t)in[i + 1] << 8 : 0) | (i + 2 < n ? in[i + 2] : 0);
        out[k++] = a[v >> 18 & 63];
        out[k++] = a[v >> 12 & 63];
        out[k++] = i + 1 < n ? a[v >> 6 & 63] : '=';
        out[k++] = i + 2 < n ? a[v & 63] : '=';
    }
    out[k] = 0;
}

static void a_signed_release_is_verified_and_anything_else_refused(void)
{
    uint8_t seed[32], secret[64], pub[32], sig[64];
    for (int i = 0; i < 32; i++)
        seed[i] = (uint8_t)(i * 7 + 1);
    crypto_ed25519_key_pair(secret, pub, seed);

    uint8_t cia[3000];
    for (size_t i = 0; i < sizeof cia; i++)
        cia[i] = (uint8_t)(i * 31);
    char hex[65], sums[200];
    rs_sha256_hex(cia, sizeof cia, hex);
    snprintf(sums, sizeof sums, "%s  romsync-0.5.1-3ds.cia\n", hex);
    size_t sums_len = strlen(sums);
    crypto_ed25519_sign(sig, secret, (const uint8_t *)sums, sums_len);
    char sig64[100], pub64[60];
    b64(sig, 64, sig64);
    b64(pub, 32, pub64);

    rs_error err;
    CHECK_INT(rs_verify_release((uint8_t *)sums, sums_len, sig64, "romsync-0.5.1-3ds.cia", cia, sizeof cia, pub64, &err),
              RS_OK);

    /* Tampered SHA256SUMS, another key, garbage signature, the real key. */
    char tampered[200];
    memcpy(tampered, sums, sums_len + 1);
    tampered[0] = tampered[0] == '0' ? '1' : '0';
    CHECK_INT(rs_verify_release((uint8_t *)tampered, sums_len, sig64, "romsync-0.5.1-3ds.cia", cia, sizeof cia, pub64,
                                &err),
              RS_ERR_REFUSED);
    CHECK(strstr(err.message, "Signature invalide") != NULL);
    CHECK_INT(rs_verify_release((uint8_t *)sums, sums_len, sig64, "romsync-0.5.1-3ds.cia", cia, sizeof cia,
                                RS_RELEASE_PUBLIC_KEY, &err),
              RS_ERR_REFUSED);
    CHECK_INT(rs_verify_release((uint8_t *)sums, sums_len, "not base64!", "romsync-0.5.1-3ds.cia", cia, sizeof cia,
                                pub64, &err),
              RS_ERR_REFUSED);

    /* Altered file, file missing from SHA256SUMS. */
    cia[10] ^= 1;
    CHECK_INT(rs_verify_release((uint8_t *)sums, sums_len, sig64, "romsync-0.5.1-3ds.cia", cia, sizeof cia, pub64, &err),
              RS_ERR_REFUSED);
    CHECK(strstr(err.message, "altéré") != NULL);
    cia[10] ^= 1;
    CHECK_INT(rs_verify_release((uint8_t *)sums, sums_len, sig64, "other.cia", cia, sizeof cia, pub64, &err),
              RS_ERR_REFUSED);
}

static void compatibility_with_the_server(void)
{
    rs_server_info info = {.api_level = 2};
    rs_strlcpy(info.min_client_version, "0.4.0", sizeof info.min_client_version);
    CHECK_INT(rs_check_compatibility(NULL, "0.5.0"), RS_COMPAT_SERVER_TOO_OLD);
    CHECK_INT(rs_check_compatibility(&info, "0.5.0"), RS_COMPAT_OK);
    info.api_level = 1;
    CHECK_INT(rs_check_compatibility(&info, "0.5.0"), RS_COMPAT_SERVER_TOO_OLD);
    info.api_level = 2;
    rs_strlcpy(info.min_client_version, "0.6.0", sizeof info.min_client_version);
    CHECK_INT(rs_check_compatibility(&info, "0.5.0"), RS_COMPAT_CLIENT_TOO_OLD);
    CHECK_INT(rs_check_compatibility(&info, "dev"), RS_COMPAT_OK);
}


/* ---- Ed25519: RFC 8032 vectors, openssl, refusals ---------------------- */

#include "../core/json_file.h"
#include "../vendor/cjson/cJSON.h"

static int hex_bytes(const char *hex, uint8_t *out, size_t size)
{
    size_t n = strlen(hex) / 2;
    if (n > size)
        return -1;
    for (size_t i = 0; i < n; i++) {
        unsigned v;
        if (sscanf(hex + 2 * i, "%2x", &v) != 1)
            return -1;
        out[i] = (uint8_t)v;
    }
    return (int)n;
}

/* L, the order of the Ed25519 group, little-endian (RFC 8032, 5.1). */
static const uint8_t ED25519_L[32] = {0xed, 0xd3, 0xf5, 0x5c, 0x1a, 0x63, 0x12, 0x58, 0xd6, 0x9c, 0xf7,
                                      0xa2, 0xde, 0xf9, 0xde, 0x14, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                                      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x10};

/* s += L (little-endian, 32 bytes). */
static void add_l(uint8_t s[32])
{
    unsigned carry = 0;
    for (int i = 0; i < 32; i++) {
        unsigned v = s[i] + ED25519_L[i] + carry;
        s[i] = (uint8_t)v;
        carry = v >> 8;
    }
}

static void rfc8032_vectors_and_refusals(void)
{
    rs_buf b = {0};
    CHECK_INT(rs_read_file(t_repo("testdata/ed25519/rfc8032-7.1.json"), &b, NULL), RS_OK);
    rs_buf_terminate(&b);
    cJSON *doc = cJSON_Parse((const char *)b.data);
    CHECK(doc != NULL);
    int count = 0;
    uint8_t first_key[32];
    const cJSON *t;
    cJSON_ArrayForEach(t, cJSON_GetObjectItemCaseSensitive(doc, "tests"))
    {
        uint8_t key[32], sig[64], tmp[64];
        uint8_t *msg = malloc(2048);
        const char *name = rs_json_str(t, "name", "");
        CHECK_INT(hex_bytes(rs_json_str(t, "public_key", ""), key, sizeof key), 32);
        CHECK_INT(hex_bytes(rs_json_str(t, "signature", ""), sig, sizeof sig), 64);
        int n = hex_bytes(rs_json_str(t, "message", ""), msg, 2048);
        CHECK(n >= 0);
        if (count == 0)
            memcpy(first_key, key, 32);
        count++;

        if (!rs_ed25519_verify(sig, key, msg, (size_t)n))
            fprintf(stderr, "    TEST %s: valid signature refused\n", name);
        CHECK(rs_ed25519_verify(sig, key, msg, (size_t)n));

        /* One byte of the signature, in R and in S. */
        int idx[] = {0, 31, 32, 63};
        for (int i = 0; i < 4; i++) {
            memcpy(tmp, sig, 64);
            tmp[idx[i]] ^= 1;
            CHECK(!rs_ed25519_verify(tmp, key, msg, (size_t)n));
        }
        /* Modified message, one more byte. */
        msg[n] = 0;
        CHECK(!rs_ed25519_verify(sig, key, msg, (size_t)n + 1));
        if (n > 0) {
            msg[0] ^= 1;
            CHECK(!rs_ed25519_verify(sig, key, msg, (size_t)n));
            msg[0] ^= 1;
        }
        /* Another public key. */
        if (count > 1)
            CHECK(!rs_ed25519_verify(sig, first_key, msg, (size_t)n));
        /* Non-canonical S + L (S >= L). */
        memcpy(tmp, sig, 64);
        add_l(tmp + 32);
        if (rs_ed25519_verify(tmp, key, msg, (size_t)n))
            fprintf(stderr, "    TEST %s: non-canonical signature (S >= L) accepted\n", name);
        CHECK(!rs_ed25519_verify(tmp, key, msg, (size_t)n));
        free(msg);
    }
    CHECK_INT(count, 5);
    cJSON_Delete(doc);
    rs_buf_free(&b);
}

/* Wrong lengths go through rs_verify_release (the API takes 64 bytes). */
static void a_signature_of_the_wrong_length_is_refused(void)
{
    rs_buf sums = {0}, sig = {0}, pub = {0};
    CHECK_INT(rs_read_file(t_repo("testdata/ed25519/openssl/SHA256SUMS"), &sums, NULL), RS_OK);
    CHECK_INT(rs_read_file(t_repo("testdata/ed25519/openssl/SHA256SUMS.sig"), &sig, NULL), RS_OK);
    CHECK_INT(rs_read_file(t_repo("testdata/ed25519/openssl/release-ed25519.pub"), &pub, NULL), RS_OK);
    rs_buf_terminate(&sig);
    rs_buf_terminate(&pub);
    uint8_t raw[64];
    CHECK_INT(rs_base64_decode((const char *)sig.data, raw, sizeof raw), 64);
    char b63[100], b65[100];
    uint8_t longer[65];
    memcpy(longer, raw, 64);
    longer[64] = 0;
    b64(raw, 63, b63);
    b64(longer, 65, b65);
    rs_error err;
    /* The file content is not checked here: a 3-byte "cia" whose hash is in SHA256SUMS. */
    CHECK_INT(rs_verify_release(sums.data, sums.len, b63, "romsync-0.5.0-3ds.cia", (const uint8_t *)"cia", 3,
                                (const char *)pub.data, &err),
              RS_ERR_REFUSED);
    CHECK_INT(rs_verify_release(sums.data, sums.len, b65, "romsync-0.5.0-3ds.cia", (const uint8_t *)"cia", 3,
                                (const char *)pub.data, &err),
              RS_ERR_REFUSED);
    CHECK_INT(rs_verify_release(sums.data, sums.len, "", "romsync-0.5.0-3ds.cia", (const uint8_t *)"cia", 3,
                                (const char *)pub.data, &err),
              RS_ERR_REFUSED);
    rs_buf_free(&sums);
    rs_buf_free(&sig);
    rs_buf_free(&pub);
}

/* SHA256SUMS signed by openssl with the commands of the release workflow
 * (testdata/ed25519/openssl/generate.sh). */
static void a_sha256sums_signed_by_openssl_is_accepted_and_only_it(void)
{
    rs_buf sums = {0}, sig = {0}, pub = {0};
    CHECK_INT(rs_read_file(t_repo("testdata/ed25519/openssl/SHA256SUMS"), &sums, NULL), RS_OK);
    CHECK_INT(rs_read_file(t_repo("testdata/ed25519/openssl/SHA256SUMS.sig"), &sig, NULL), RS_OK);
    CHECK_INT(rs_read_file(t_repo("testdata/ed25519/openssl/release-ed25519.pub"), &pub, NULL), RS_OK);
    rs_buf_terminate(&sig);
    rs_buf_terminate(&pub);
    rs_error err;
    CHECK_INT(rs_verify_release(sums.data, sums.len, (const char *)sig.data, "romsync-0.5.0-3ds.cia",
                                (const uint8_t *)"cia", 3, (const char *)pub.data, &err),
              RS_OK);
    CHECK_INT(rs_verify_release(sums.data, sums.len, (const char *)sig.data, "romsync-0.5.0-3ds.cia",
                                (const uint8_t *)"cia", 3, RS_RELEASE_PUBLIC_KEY, &err),
              RS_ERR_REFUSED);
    sums.data[0] ^= 1;
    CHECK_INT(rs_verify_release(sums.data, sums.len, (const char *)sig.data, "romsync-0.5.0-3ds.cia",
                                (const uint8_t *)"cia", 3, (const char *)pub.data, &err),
              RS_ERR_REFUSED);
    rs_buf_free(&sums);
    rs_buf_free(&sig);
    rs_buf_free(&pub);
}

/* testdata/ed25519/verdicts.json: the same cases as romsync_core's
 * ed25519_test.dart, which must give the same verdicts (non-regression).
 * Keys and signatures of another length are invalid, as verifyEd25519. */
static void verdicts_are_the_same_as_the_dart_client(void)
{
    rs_buf b = {0};
    CHECK_INT(rs_read_file(t_repo("testdata/ed25519/verdicts.json"), &b, NULL), RS_OK);
    rs_buf_terminate(&b);
    cJSON *doc = cJSON_Parse((const char *)b.data);
    CHECK(doc != NULL);
    int count = 0;
    const cJSON *c;
    cJSON_ArrayForEach(c, cJSON_GetObjectItemCaseSensitive(doc, "cases"))
    {
        uint8_t key[33], sig[66];
        uint8_t *msg = malloc(2048);
        int nk = hex_bytes(rs_json_str(c, "public_key", ""), key, sizeof key);
        int ns = hex_bytes(rs_json_str(c, "signature", ""), sig, sizeof sig);
        int nm = hex_bytes(rs_json_str(c, "message", ""), msg, 2048);
        CHECK(nm >= 0);
        bool got = nk == 32 && ns == 64 && rs_ed25519_verify(sig, key, msg, (size_t)nm);
        bool want = rs_json_bool(c, "valid", false);
        if (got != want)
            fprintf(stderr, "    %s: got %d, want %d\n", rs_json_str(c, "name", ""), got, want);
        CHECK(got == want);
        count++;
        free(msg);
    }
    CHECK(count > 60);
    cJSON_Delete(doc);
    rs_buf_free(&b);
}

void run_update_tests(void)
{
    RUN(versions_order_no_downgrade_no_pre_release_no_dev_update);
    RUN(the_built_in_key_is_keys_release_ed25519_pub);
    RUN(base64_and_sums);
    RUN(a_signed_release_is_verified_and_anything_else_refused);
    RUN(compatibility_with_the_server);
    RUN(rfc8032_vectors_and_refusals);
    RUN(a_signature_of_the_wrong_length_is_refused);
    RUN(a_sha256sums_signed_by_openssl_is_accepted_and_only_it);
    RUN(verdicts_are_the_same_as_the_dart_client);
}
