/*
 * size_rule.h - comparing a local save with the active version after the
 * size rules of the server (docs/SPEC.md, "Taille réelle";
 * server/internal/syncrule/size.go), as romsync_core's size_rule.dart.
 */
#ifndef RS_SIZE_RULE_H
#define RS_SIZE_RULE_H

#include <stdbool.h>
#include <stdint.h>

#include "api.h"
#include "rs.h"

/* Whether b is non-empty and made of a single 0xFF or 0x00 byte value. */
bool rs_is_padding(const uint8_t *b, size_t n);

/* Downloads the active version's content (only called when needed). */
typedef rs_status (*rs_fetch_fn)(void *ctx, rs_buf *out, rs_error *err);

/* *same receives whether uploading raw (SHA-256 hash) would bring nothing
 * new compared with the active version: a save padded beyond the chip size
 * (TWiLight Menu++ pads with 0x00) is compared once cut to the chip size, as
 * the server would cut it; a smaller save is the same as an active version
 * whose excess is only padding (a 32 KiB FRAM seen as 64 KiB), which fetch
 * then downloads. chip_size is 0 when unknown. */
rs_status rs_same_content_as_active(const uint8_t *raw, size_t n, const char *hash, const rs_version *active,
                                    int64_t chip_size, rs_fetch_fn fetch, void *fetch_ctx, bool *same,
                                    rs_error *err);

#endif
