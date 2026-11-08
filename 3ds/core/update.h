/*
 * update.h - updates of the homebrew and compatibility with the server
 * (docs/SPEC.md, "Mises à jour" and "Compatibilité"), as romsync_core's
 * release.dart.
 */
#ifndef RS_UPDATE_H
#define RS_UPDATE_H

#include <stdbool.h>
#include <stdint.h>

#include "api.h"
#include "rs.h"

/* Ed25519 public key of the releases (base64), the same as
 * keys/release-ed25519.pub (a test checks it). */
#define RS_RELEASE_PUBLIC_KEY "XefK8zbkiB+PmUAtb43o6JR3AawkvJdgSBIv2me7kJQ="

/* Server level needed by this client: 2 is X-Activate. */
#define RS_REQUIRED_API_LEVEL 2

typedef struct {
    int major, minor, patch;
    char pre[32]; /* "" for a final release */
} rs_release_version;

/* Parses "0.5.0", "v0.5.0" or "0.5.0-rc1". */
bool rs_version_parse(const char *s, rs_release_version *out);
/* -1, 0 or 1; a pre-release is older than its release. */
int rs_version_compare(const rs_release_version *a, const rs_release_version *b);
/* Whether update should be offered at current: a final release, strictly
 * newer (never a downgrade); never for a development build ("dev"). */
bool rs_is_update(const char *update, const char *current);

/* Decodes standard base64 (spaces and newlines ignored); returns the
 * number of bytes, or -1 on an invalid input or a too small buffer. */
int rs_base64_decode(const char *in, uint8_t *out, size_t size);

/* The SHA-256 (hex) of name in a sha256sum output, into hex[65]. */
bool rs_sum_for(const char *sums, size_t len, const char *name, char hex[65]);

/* Checks a downloaded release file: the Ed25519 signature of sums
 * (signature_b64: the content of SHA256SUMS.sig) with public_key_b64, then
 * the SHA-256 of data against its line in sums. RS_ERR_REFUSED with a
 * message on any mismatch. */
rs_status rs_verify_release(const uint8_t *sums, size_t sums_len, const char *signature_b64,
                            const char *file_name, const uint8_t *data, size_t len, const char *public_key_b64,
                            rs_error *err);

typedef enum {
    RS_COMPAT_OK,
    RS_COMPAT_SERVER_TOO_OLD, /* no GET /server, or api_level < 2 */
    RS_COMPAT_CLIENT_TOO_OLD, /* older than the server's min_client_version */
} rs_compatibility;

/* info is NULL for a server older than 0.5.0. */
rs_compatibility rs_check_compatibility(const rs_server_info *info, const char *client_version);

#endif
