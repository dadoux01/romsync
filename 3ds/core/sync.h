/*
 * sync.h - the sync protocol of docs/SPEC.md, "Protocole de
 * synchronisation", ported from romsync_core (client/packages/romsync_core,
 * lib/src/sync/engine.dart) with the same decisions and the same tests.
 *
 * On the 3DS the app syncs every game at startup (rs_engine_prepare on each
 * one), since it cannot watch the game while it runs.
 */
#ifndef RS_SYNC_H
#define RS_SYNC_H

#include <stdbool.h>

#include "api.h"
#include "profile.h"
#include "queue.h"
#include "state.h"

/* A local ROM and its save file, ready to be synced. */
typedef struct {
    char rom_path[RS_PATH_MAX];   /* identifies the ROM (key of the user's choices) */
    char title[64];
    char game_id[RS_GAME_ID_MAX]; /* detected, or forced "x:" identifier */
    char save_path[RS_PATH_MAX];
    const rs_profile *profile;
    char emulator[32];            /* sent as X-Emulator */
    /* Several ROMs share the identifier and the user has not chosen yet
     * between sharing and separating their save: not synced. */
    bool needs_choice;
    /* Why the ROM cannot be synced, or "" when it can. */
    char unavailable[160];
} rs_entry;

typedef enum {
    RS_EVENT_UPLOADED,
    RS_EVENT_QUEUED,
    RS_EVENT_DOWNLOADED,
    RS_EVENT_UP_TO_DATE,
    RS_EVENT_OFFLINE,
    RS_EVENT_FAILED,
    RS_EVENT_NEEDS_CHOICE, /* an automatic upload was held back by a divergence */
} rs_event_kind;

/* What the user chooses after a divergence (docs/SPEC.md, "Divergence"). */
typedef enum {
    RS_CHOICE_NONE,   /* not asked yet, or "Plus tard" */
    RS_CHOICE_LOCAL,  /* "Envoyer ma save locale": sent, becomes active */
    RS_CHOICE_SERVER, /* "Prendre celle du serveur": the local save is sent as
                       * an inactive version, then the server's is downloaded
                       * (the local file is copied into .backup first) */
} rs_choice;

/* Two devices played without syncing: the local save changed, and the
 * server's active version is neither the one this device last synced nor
 * the same content. Nothing is sent nor overwritten until the user chooses. */
typedef struct {
    char game_id[RS_GAME_ID_MAX];
    char save_path[RS_PATH_MAX];
    rs_version server; /* the server's active version */
} rs_divergence;

typedef struct {
    rs_api *api;
    rs_state_store *states;
    rs_queue *queue;
    int keep_backups; /* copies kept in .backup per save (10 by default) */
    /* Console clock (injectable for the tests). */
    rs_time (*now)(void *ctx);
    void *now_ctx;
    /* Optional: called for each thing the engine does (interface, log). */
    void (*on_event)(void *ctx, rs_event_kind kind, const char *game_id, const char *message);
    void *event_ctx;
} rs_engine;

/* The raw content of a local save file. */
typedef struct {
    bool exists;
    rs_buf raw;     /* decoded with the entry's profile */
    char hash[65];  /* SHA-256 of raw */
} rs_local_save;

typedef struct {
    int sent;
    bool offline;
    bool unauthorized;
    int failures;            /* uploads refused for good (kept in queue/failed) */
    char failure_message[256];
    /* Saves whose automatic uploads were held back by a divergence: they
     * stay in the queue until the user chooses. */
    int held;
    rs_divergence first_held;
} rs_flush_result;

typedef struct {
    bool offline;  /* the server could not be reached: changes wait in the queue */
    bool uploaded;
    bool downloaded;
    char backup_path[RS_PATH_MAX]; /* copy of the replaced local save, or "" */
    char message[256];
    /* The user must choose: nothing was sent nor overwritten. Call
     * rs_engine_prepare again with the choice. */
    bool needs_choice;
    rs_divergence divergence;
} rs_prepare_result;

/* Corrected current time: console clock + measured gap with the server. */
rs_time rs_engine_now(const rs_engine *e);

rs_status rs_read_local_save(const rs_entry *entry, rs_local_save *out, rs_error *err);
void rs_local_save_free(rs_local_save *s);

/* Step 1: sends the queued uploads, oldest first, while the server
 * answers. The base version of each upload is the save's last synced
 * version when it leaves, so that uploads queued offline chain. */
rs_status rs_engine_flush(rs_engine *e, rs_flush_result *out, rs_error *err);

/* Queues save for entry unless the same content is already queued.
 * X-Saved-At is the corrected time at which RomSync first sees this
 * content (3DS: the file's date is not reliable, see 3ds/README.md). */
rs_status rs_engine_enqueue(rs_engine *e, const rs_entry *entry, const rs_local_save *save, bool *queued,
                            rs_error *err);

/* Syncs one save (steps 1 to 4 of "Avant le lancement"): sends local
 * changes, then downloads a newer server version into the save file, after
 * a copy into .backup. RS_ERR_REFUSED when the entry cannot be synced.
 * When the local save diverges and choice is RS_CHOICE_NONE, nothing is
 * sent nor overwritten and out->needs_choice is set. */
rs_status rs_engine_prepare(rs_engine *e, const rs_entry *entry, size_t chip_size, rs_choice choice,
                            rs_prepare_result *out, rs_error *err);

/* The server is known to be unreachable (an earlier game of the same
 * startup pass found it so): only queues a local change of entry, without
 * waiting for a network timeout on every game. */
rs_status rs_engine_offline_pass(rs_engine *e, const rs_entry *entry, rs_prepare_result *out, rs_error *err);

/* ---- Status shown in the game list ------------------------------------- */

typedef enum {
    RS_STATUS_UP_TO_DATE,
    RS_STATUS_TO_UPLOAD,
    RS_STATUS_TO_DOWNLOAD,
    RS_STATUS_OFFLINE,
    RS_STATUS_NEEDS_CHOICE,
    RS_STATUS_UNAVAILABLE,
    RS_STATUS_NO_SAVE,
    RS_STATUS_DIVERGED, /* an upload is held back until the user chooses */
} rs_save_status;

/* Status of a save, as romsync_core's computeStatus. local_hash is NULL
 * without a local save; remote is NULL when the server does not know the
 * game; online tells whether the server answered. */
rs_save_status rs_compute_status(bool needs_choice, bool unavailable, const char *local_hash,
                                 const rs_save_state *state, const rs_remote_game *remote, int queued,
                                 bool online, bool held);
const char *rs_status_label(rs_save_status s);

/* ---- .backup copies ---------------------------------------------------- */

/* Copies save_path (when it exists) into the .backup folder next to it,
 * named "<file>.<date>", and keeps only the `keep` newest copies. copy
 * receives the copy's path, or "" when there was no file. */
rs_status rs_backup(const char *save_path, rs_time now, int keep, char *copy, size_t copy_size, rs_error *err);
/* Number of backup copies of save_path; names, when not NULL, receives
 * the newest one's path. */
int rs_backup_count(const char *save_path, char *newest, size_t newest_size);

/* ---- Changing the save file of a game ---------------------------------- */

/* Whether the save file of entry exists but was never synced by RomSync for
 * this game: probably an old save (e.g. another TWiLight Menu++ save slot).
 * Sending it would only add a stale divergent version to the history, so
 * the user is warned and offered to set it aside (docs/SPEC.md,
 * "Changement d'émulateur"). */
bool rs_is_stale_save(const rs_entry *entry, const rs_state_store *states);
/* Moves save_path into its .backup folder. */
rs_status rs_set_aside(const char *save_path, rs_time now, int keep, char *copy, size_t copy_size,
                       rs_error *err);

#endif
