/*
 * app.h - state and actions of the 3DS app. main.c draws the screens and
 * calls these actions; everything that does not depend on libctru lives in
 * ../core.
 */
#ifndef RS_APP_H
#define RS_APP_H

#include <stdbool.h>

#include "../core/api.h"
#include "../core/config.h"
#include "../core/library.h"
#include "../core/profile.h"
#include "../core/queue.h"
#include "../core/state.h"
#include "../core/sync.h"

/* Everything RomSync keeps on the SD card is in this folder. */
#define APP_DIR "sdmc:/3ds/romsync"
/* The folder that stands for "sd:/" in TWiLight Menu++'s paths. */
#define SD_ROOT "sdmc:/"

/* What the game list shows for one game. */
typedef struct {
    rs_save_status status;
    bool synced;        /* a sync ran for this game since the start */
    bool error;         /* the last sync failed: see message */
    bool conflict;      /* "conflit résolu automatiquement" on the server */
    char message[160];
} game_view;

typedef struct {
    rs_config config;
    rs_state_store states;
    rs_queue queue;
    rs_profiles profiles;
    const rs_profile *twilight;
    rs_api api;
    rs_engine engine;

    rs_scan_result scan;
    rs_library lib;
    game_view *views; /* one per lib.games entry */

    bool online;      /* the server answered during the last sync */
    char status_line[128];
} app;

/* Loads the settings, state, queue and profiles. */
bool app_init(app *a);
void app_exit(app *a);

/* First start: server address, pairing code and device name. Returns false
 * when the user gives up. */
bool app_pair(app *a);
/* Asks for the ROM folders (first start, or from the settings). */
void app_choose_folders(app *a);
/* Scans the ROM folders again and rebuilds the game list. */
void app_rescan(app *a);
/* Sends the modified saves, then downloads the newer ones (every game). */
void app_sync_all(app *a);
/* Same for one game of the list. */
void app_sync_one(app *a, int index);
/* "Partager" or "Séparer" for a ROM sharing its identifier. */
void app_choose_sharing(app *a, int index);
/* Settings menu. */
void app_settings(app *a);

#endif
