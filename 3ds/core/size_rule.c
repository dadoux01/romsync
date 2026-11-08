/*
 * size_rule.c - see size_rule.h.
 */
#include "size_rule.h"

#include <string.h>

#include "sha.h"

bool rs_is_padding(const uint8_t *b, size_t n)
{
    if (n == 0 || (b[0] != 0xFF && b[0] != 0x00))
        return false;
    for (size_t i = 1; i < n; i++)
        if (b[i] != b[0])
            return false;
    return true;
}

rs_status rs_same_content_as_active(const uint8_t *raw, size_t n, const char *hash, const rs_version *active,
                                    int64_t chip_size, rs_fetch_fn fetch, void *fetch_ctx, bool *same,
                                    rs_error *err)
{
    *same = strcmp(hash, active->sha256) == 0;
    size_t chip = chip_size > 0 ? (size_t)chip_size : 0;
    if (*same || chip == 0 || n == chip)
        return RS_OK;
    if (n > chip) {
        /* Cut to the chip size when the excess is only padding. */
        if (rs_is_padding(raw + chip, n - chip)) {
            char cut[65];
            rs_sha256_hex(raw, chip, cut);
            *same = strcmp(cut, active->sha256) == 0;
        }
        return RS_OK;
    }
    /* Smaller: the server shrinks the chip size when the active version's
     * excess is only padding; the progression is then the same if the rest
     * is equal. */
    if (active->size <= n)
        return RS_OK;
    rs_buf act = {0};
    rs_status st = fetch(fetch_ctx, &act, err);
    if (st == RS_OK)
        *same = act.len > n && rs_is_padding(act.data + n, act.len - n) && memcmp(act.data, raw, n) == 0;
    rs_buf_free(&act);
    return st;
}
