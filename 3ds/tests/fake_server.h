/*
 * fake_server.h - in-memory RomSync server implementing the sync rules,
 * for the unit tests of the engine (the end-to-end test uses the real Go
 * server). Same behaviour as romsync_core's test/support/fake_server.dart.
 */
#ifndef RS_FAKE_SERVER_H
#define RS_FAKE_SERVER_H

#include <stdbool.h>
#include <stdint.h>

#include "../core/api.h"
#include "../core/http.h"

#define FAKE_MAX 64

typedef struct {
    int64_t id;
    char code[RS_GAME_ID_MAX];
    rs_buf data;
    char sha[65];
    rs_time saved_at;
    int64_t base; /* 0 = none */
    bool conflict;
} fake_version;

typedef struct {
    fake_version versions[FAKE_MAX];
    int version_count;
    struct {
        char code[RS_GAME_ID_MAX];
        int64_t id;
    } active[FAKE_MAX];
    int active_count;
    struct {
        char upload_id[40];
        int64_t id;
    } upload_ids[FAKE_MAX];
    int upload_id_count;
    /* Chip size of each game: set by its first save (size rules of
     * server/internal/syncrule/size.go). */
    struct {
        char code[RS_GAME_ID_MAX];
        size_t size;
    } chips[FAKE_MAX];
    int chip_count;

    bool online;
    bool drop_next_upload_response; /* process the upload, lose the answer */
    char refuse_uploads[32];        /* when set, answer 409 with this code */
    int upload_requests;
    rs_time server_now;             /* sent in the Date header when not 0 */
    int64_t seq;
} fake_server;

void fake_init(fake_server *s);
void fake_free(fake_server *s);
/* Adds a version made by another device and makes it active. */
const fake_version *fake_add_version(fake_server *s, const char *code, const uint8_t *data, size_t len,
                                     rs_time saved_at);
const fake_version *fake_active(const fake_server *s, const char *code);
/* The transport plugged into rs_api.send (ctx = the fake_server). */
rs_status fake_send(void *ctx, const rs_http_request *req, rs_http_response *res, rs_error *err);

#endif
