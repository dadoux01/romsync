/*
 * api.h - client of the RomSync REST API (docs/SPEC.md, "API REST"),
 * authenticated with the device token.
 */
#ifndef RS_API_H
#define RS_API_H

#include <stdbool.h>
#include <stdint.h>

#include "clock.h"
#include "http.h"
#include "nds.h"
#include "rs.h"

typedef struct {
    int64_t id;
    char game_code[RS_GAME_ID_MAX];
    char sha256[65];
    size_t size;
    rs_time saved_at;
    char device_name[64];
    bool conflict;
} rs_version;

/* The user's choice sent with an upload (X-Activate). */
typedef enum {
    RS_ACTIVATE_AUTO,   /* no header: most recent wins */
    RS_ACTIVATE_ALWAYS, /* "true": the upload becomes active */
    RS_ACTIVATE_NEVER,  /* "false": kept as an inactive version */
} rs_activation;

typedef struct {
    rs_version version;
    bool created; /* false: same content as the active version */
    bool active;  /* the upload became the active version */
    bool conflict;/* it diverged from the active version */
} rs_upload_result;

typedef struct {
    char code[RS_GAME_ID_MAX];
    char title[64];
    bool conflict;     /* the latest upload diverged ("conflit résolu automatiquement") */
    bool has_active;
    rs_version active;
    int64_t chip_size; /* 0 when unknown */
} rs_remote_game;

typedef struct {
    char base_url[256]; /* "http://192.168.1.68:8085", no trailing slash */
    char token[128];    /* device token, "" before pairing */
    rs_http_send_fn send;
    void *send_ctx;
    /* When set, every response's "Date" header updates this clock gap,
     * measured against now(). */
    rs_clock *clock;
    rs_time (*now)(void *ctx);
    void *now_ctx;
} rs_api;

/* Adds "http://" when missing, removes trailing slashes, checks the
 * scheme and host. */
bool rs_api_normalize_url(const char *in, char *out, size_t size);

/* POST /pair: exchanges a pairing code for a device token. */
rs_status rs_api_pair(rs_api *api, const char *code, const char *name, const char *platform, char *token,
                      size_t token_size, rs_error *err);
/* GET /games/{id}/active. *exists is false when the game or its active
 * version does not exist yet (404). chip_size (may be NULL) receives the
 * game's chip size, 0 when unknown. */
rs_status rs_api_active(rs_api *api, const char *game_id, rs_version *out, bool *exists, int64_t *chip_size,
                        rs_error *err);
/* POST /games/{id}/versions with the raw save. base_version 0 = none. */
rs_status rs_api_upload(rs_api *api, const char *game_id, const uint8_t *data, size_t len, rs_time saved_at,
                        const char *upload_id, int64_t base_version, const char *emulator, const char *title,
                        rs_activation activate, rs_upload_result *out, rs_error *err);
/* GET /versions/{id}/content, checked against X-Content-SHA256. */
rs_status rs_api_download(rs_api *api, int64_t version_id, rs_buf *out, rs_error *err);
/* GET /games. *games is malloc'ed (free it). */
rs_status rs_api_games(rs_api *api, rs_remote_game **games, int *count, rs_error *err);

/* Percent-encodes s like JavaScript's encodeComponent (UTF-8 bytes). */
void rs_url_encode(const char *s, char *out, size_t size);

#endif
