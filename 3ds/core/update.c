/*
 * update.c - see update.h.
 */
#include "update.h"

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../vendor/monocypher/monocypher-ed25519.h"
#include "sha.h"

static bool parse_number(const char **p, int *out)
{
    const char *s = *p;
    if (!isdigit((unsigned char)*s) || (s[0] == '0' && isdigit((unsigned char)s[1])))
        return false;
    long v = 0;
    while (isdigit((unsigned char)*s)) {
        v = v * 10 + (*s++ - '0');
        if (v > 1000000)
            return false;
    }
    *out = (int)v;
    *p = s;
    return true;
}

bool rs_version_parse(const char *s, rs_release_version *out)
{
    memset(out, 0, sizeof *out);
    if (*s == 'v')
        s++;
    if (!parse_number(&s, &out->major) || *s++ != '.' || !parse_number(&s, &out->minor) || *s++ != '.' ||
        !parse_number(&s, &out->patch))
        return false;
    if (*s == 0)
        return true;
    if (*s++ != '-' || !*s || strlen(s) >= sizeof out->pre)
        return false;
    for (const char *c = s; *c; c++)
        if (!isalnum((unsigned char)*c) && *c != '.')
            return false;
    rs_strlcpy(out->pre, s, sizeof out->pre);
    return true;
}

int rs_version_compare(const rs_release_version *a, const rs_release_version *b)
{
    int x[3] = {a->major, a->minor, a->patch}, y[3] = {b->major, b->minor, b->patch};
    for (int i = 0; i < 3; i++)
        if (x[i] != y[i])
            return x[i] < y[i] ? -1 : 1;
    int c = strcmp(a->pre, b->pre);
    if (c == 0)
        return 0;
    if (!a->pre[0])
        return 1;
    if (!b->pre[0])
        return -1;
    return c < 0 ? -1 : 1;
}

bool rs_is_update(const char *update, const char *current)
{
    rs_release_version u, c;
    return rs_version_parse(update, &u) && rs_version_parse(current, &c) && !u.pre[0] &&
           rs_version_compare(&u, &c) > 0;
}

int rs_base64_decode(const char *in, uint8_t *out, size_t size)
{
    static const char alphabet[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    uint32_t acc = 0;
    int bits = 0, pad = 0;
    size_t n = 0;
    for (const char *p = in; *p; p++) {
        if (isspace((unsigned char)*p))
            continue;
        if (*p == '=') {
            pad++;
            continue;
        }
        const char *k = strchr(alphabet, *p);
        if (!k || !*p || pad)
            return -1;
        acc = (acc << 6) | (uint32_t)(k - alphabet);
        bits += 6;
        if (bits >= 8) {
            bits -= 8;
            if (n >= size)
                return -1;
            out[n++] = (uint8_t)(acc >> bits);
        }
    }
    return pad > 2 ? -1 : (int)n;
}

bool rs_sum_for(const char *sums, size_t len, const char *name, char hex[65])
{
    size_t nlen = strlen(name);
    const char *p = sums, *end = sums + len;
    while (p < end) {
        const char *eol = memchr(p, '\n', (size_t)(end - p));
        if (!eol)
            eol = end;
        size_t l = (size_t)(eol - p);
        if (l > 0 && p[l - 1] == '\r')
            l--;
        /* "<64 hex>  <name>" or "<64 hex> *<name>" */
        if (l == 66 + nlen && p[64] == ' ' && (p[65] == ' ' || p[65] == '*') && memcmp(p + 66, name, nlen) == 0) {
            bool ok = true;
            for (int i = 0; i < 64; i++) {
                if (!isxdigit((unsigned char)p[i]))
                    ok = false;
                hex[i] = (char)tolower((unsigned char)p[i]);
            }
            hex[64] = 0;
            if (ok)
                return true;
        }
        p = eol + 1;
    }
    return false;
}

rs_status rs_verify_release(const uint8_t *sums, size_t sums_len, const char *signature_b64,
                            const char *file_name, const uint8_t *data, size_t len, const char *public_key_b64,
                            rs_error *err)
{
    uint8_t sig[64], key[32];
    if (rs_base64_decode(signature_b64, sig, sizeof sig) != 64 ||
        rs_base64_decode(public_key_b64, key, sizeof key) != 32)
        return rs_fail(err, RS_ERR_REFUSED, "Signature illisible : mise à jour refusée.");
    if (crypto_ed25519_check(sig, key, sums, sums_len) != 0)
        return rs_fail(err, RS_ERR_REFUSED,
                       "Signature invalide : cette mise à jour ne vient pas de RomSync, elle est refusée.");
    char expected[65], actual[65];
    if (!rs_sum_for((const char *)sums, sums_len, file_name, expected))
        return rs_fail(err, RS_ERR_REFUSED, "%s ne figure pas dans SHA256SUMS : mise à jour refusée.", file_name);
    rs_sha256_hex(data, len, actual);
    if (strcmp(actual, expected) != 0)
        return rs_fail(err, RS_ERR_REFUSED,
                       "Le fichier téléchargé est altéré (hash différent) : mise à jour refusée.");
    return RS_OK;
}

rs_compatibility rs_check_compatibility(const rs_server_info *info, const char *client_version)
{
    if (!info || info->api_level < RS_REQUIRED_API_LEVEL)
        return RS_COMPAT_SERVER_TOO_OLD;
    rs_release_version min, me;
    if (rs_version_parse(info->min_client_version, &min) && rs_version_parse(client_version, &me) &&
        rs_version_compare(&me, &min) < 0)
        return RS_COMPAT_CLIENT_TOO_OLD;
    return RS_COMPAT_OK;
}
