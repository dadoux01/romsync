/*
 * queue.h - uploads waiting for the server (docs/SPEC.md, "Hors ligne").
 *
 * First in, first out, persisted in <dir>/queue.json with a copy of each
 * queued content in <dir>/<upload id>.bin: the save file may change again
 * before the upload leaves. The upload id (a UUID) is generated once, when
 * the save is queued, and reused for every retry, so that a retry after a
 * cut connection never creates a duplicate version on the server.
 */
#ifndef RS_QUEUE_H
#define RS_QUEUE_H

#include <stdint.h>

#include "clock.h"
#include "nds.h"
#include "rs.h"

/* How an upload is activated on the server (docs/SPEC.md, "Divergence"). */
typedef enum {
    RS_UPLOAD_AUTO,    /* "most recent wins"; held back when it would diverge */
    RS_UPLOAD_LOCAL,   /* the user chose the local save: X-Activate: true */
    RS_UPLOAD_ARCHIVE, /* the user chose the server's save: X-Activate: false */
} rs_upload_mode;

typedef struct {
    char upload_id[37];
    char game_id[RS_GAME_ID_MAX];
    char save_path[RS_PATH_MAX];
    char sha256[65]; /* of the queued raw content */
    size_t size;
    rs_time saved_at;
    rs_time created_at;
    char emulator[32];
    char title[64];
    rs_upload_mode mode;
    /* An automatic upload held back because it diverges from the server:
     * it waits for the user's choice. */
    bool held;
} rs_upload;

typedef struct {
    char dir[RS_PATH_MAX];
    rs_upload *items;
    int count;
    char warning[256];
} rs_queue;

rs_status rs_queue_open(rs_queue *q, const char *dir, rs_error *err);
void rs_queue_close(rs_queue *q);

/* Queues data with a new upload id; *added receives a copy of the entry
 * (may be NULL). */
rs_status rs_queue_add(rs_queue *q, const char *game_id, const char *save_path, const uint8_t *data,
                       size_t len, const char *sha256, rs_time saved_at, const char *emulator,
                       const char *title, rs_time now, rs_upload *added, rs_error *err);
/* Reads the queued content of an upload. */
rs_status rs_queue_content(const rs_queue *q, const rs_upload *u, rs_buf *out, rs_error *err);
/* Removes a sent upload and its content. */
rs_status rs_queue_remove(rs_queue *q, const char *upload_id, rs_error *err);
/* Sets the mode of the uploads of save_path and game_id (and clears
 * their held flag): the user's choice after a divergence. */
rs_status rs_queue_set_mode(rs_queue *q, const char *save_path, const char *game_id, rs_upload_mode mode,
                            rs_error *err);
/* Marks the automatic uploads of save_path as held. */
rs_status rs_queue_mark_held(rs_queue *q, const char *save_path, rs_error *err);
/* Whether an upload of save_path is held. */
bool rs_queue_held_for(const rs_queue *q, const char *save_path);
/* Number of uploads waiting for save_path. */
int rs_queue_count_for(const rs_queue *q, const char *save_path);
/* Whether the same content is already queued for save_path and game_id. */
bool rs_queue_has(const rs_queue *q, const char *save_path, const char *game_id, const char *sha256);

/* A random version 4 UUID, "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx". */
void rs_uuid4(char out[37]);

#endif
