/*
 * state.h - sync state of each local save file (docs/SPEC.md, "État local
 * par fichier de save"), persisted in state.json.
 *
 * The state is kept per save file, not per game: several ROMs can share a
 * game identifier, each with its own save file. The file also keeps the
 * last measured gap between the console clock and the server.
 */
#ifndef RS_STATE_H
#define RS_STATE_H

#include <stdbool.h>
#include <stdint.h>

#include "clock.h"
#include "nds.h"
#include "rs.h"

typedef struct {
    char save_path[RS_PATH_MAX];
    char game_id[RS_GAME_ID_MAX]; /* identifier the save is synced with */
    int64_t version_id;           /* last_synced_version_id, 0 = none */
    char hash[65];                /* last_synced_hash: SHA-256 of the raw local save */
    rs_time synced_at;
} rs_save_state;

typedef struct {
    char path[RS_PATH_MAX]; /* state.json */
    rs_save_state *items;
    int count;
    rs_clock clock;         /* persisted gap with the server clock */
    char warning[256];      /* set when a corrupted file was moved aside */
} rs_state_store;

rs_status rs_state_open(rs_state_store *s, const char *path, rs_error *err);
void rs_state_close(rs_state_store *s);

/* State recorded for save_path, or NULL. */
const rs_save_state *rs_state_get(const rs_state_store *s, const char *save_path);
/* The state of save_path only when it was synced with game_id: a state
 * recorded under another identifier (ROM separated or re-shared) is
 * ignored, like romsync_core's SyncEngine.stateOf. */
const rs_save_state *rs_state_for(const rs_state_store *s, const char *save_path, const char *game_id);

/* Records a successful sync and saves the file. */
rs_status rs_state_record(rs_state_store *s, const char *save_path, const char *game_id, int64_t version_id,
                          const char *hash, rs_time at, rs_error *err);
rs_status rs_state_forget(rs_state_store *s, const char *save_path, rs_error *err);
rs_status rs_state_save(rs_state_store *s, rs_error *err);

#endif
