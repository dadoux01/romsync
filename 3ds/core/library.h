/*
 * library.h - the DS ROMs found on the SD card and their save files.
 *
 * rs_scan lists the ROMs of the configured folders and reads their header;
 * rs_build_library turns them into sync entries: TWiLight Menu++ save file,
 * ROMs sharing an identifier (docs/SPEC.md, "Cas particuliers"), and save
 * slot changes.
 */
#ifndef RS_LIBRARY_H
#define RS_LIBRARY_H

#include "config.h"
#include "nds.h"
#include "profile.h"
#include "state.h"
#include "sync.h"

typedef struct {
    char path[RS_PATH_MAX];
    char title[64];
    char detected_id[RS_GAME_ID_MAX]; /* cartridge code or "h:<sha1>" */
    long long size;
} rs_rom;

typedef struct {
    rs_rom *roms;
    int count;
    /* ROMs found in each configured folder (same order as the config), so
     * that the app can say "no ROM in this folder" instead of an empty list. */
    int per_folder[RS_MAX_FOLDERS];
    char error[256]; /* first unreadable folder or ROM, or "" */
} rs_scan_result;

/* Lists the DS ROMs (.nds, .dsi, .ids, .srl) of the configured folders.
 * Hidden folders and "saves" folders are skipped. Homebrew identifiers
 * come from the cache in c when the size did not change (c is updated). */
void rs_scan(rs_config *c, rs_scan_result *out);
void rs_scan_free(rs_scan_result *r);
/* Whether name has a DS ROM extension. */
bool rs_is_rom_file(const char *name);

/* A library entry with what the interface needs on top of rs_entry. */
typedef struct {
    rs_entry entry;
    char detected_id[RS_GAME_ID_MAX];
    int shared_count; /* other ROMs with the same detected identifier */
    int slot;         /* TWiLight Menu++ save slot (0 = ".sav") */
    /* The save slot differs from the one seen before and its file was never
     * synced for this game: the user must choose to set it aside or send it. */
    bool stale_after_slot_change;
} rs_game;

typedef struct {
    rs_game *games;
    int count;
} rs_library;

/* Builds the entries of the scanned ROMs. profile is the "twilight"
 * conversion profile; sd_root stands for "sd:/" (see twilight.h). */
void rs_build_library(const rs_scan_result *scan, const rs_config *c, const rs_state_store *states,
                      const rs_profile *profile, const char *sd_root, rs_library *out);
void rs_library_free(rs_library *l);

#endif
