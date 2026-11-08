/*
 * twilight.h - where TWiLight Menu++ and the NTR forwarder (YANBF) keep the
 * saves of DS games, read from their settings on the SD card.
 *
 * Verified in the sources (see 3ds/README.md, "TWiLight Menu++"):
 *   - sd:/_nds/TWiLightMenu/settings.ini, [SRLOADER] SAVE_LOCATION:
 *       0 (default) <ROM folder>/saves/, 1 next to the ROM,
 *       2 sd:/_nds/TWiLightMenu/saves/;
 *   - save name: ROM file name with its extension replaced by ".sav", or
 *     ".sav1" to ".sav9" for the per-game save slot ([GAMESETTINGS]
 *     SAVE_NUMBER in sd:/_nds/TWiLightMenu/gamesettings/<ROM file>.ini),
 *     except with SAVE_LOCATION=1 where the slot is ignored;
 *   - the NTR forwarder uses the same rules with its own settings:
 *     sd:/_nds/ntr_forwarder.ini [NTR-FORWARDER] SAVE_LOCATION and
 *     sd:/_nds/ntr-forwarder/gamesettings/<ROM file>.ini (its slot also
 *     applies next to the ROM).
 *
 * sd_root is the folder that stands for "sd:/": "sdmc:/" on the 3DS, a
 * temporary folder in the tests.
 */
#ifndef RS_TWILIGHT_H
#define RS_TWILIGHT_H

#include <stdbool.h>
#include <stddef.h>

#include "rs.h"

/* Reads "key = value" in [section] of an INI file (TWiLight Menu++'s
 * format). False when the file, section or key is missing. */
bool rs_ini_get(const char *path, const char *section, const char *key, char *out, size_t size);
int rs_ini_get_int(const char *path, const char *section, const char *key, int def);

typedef enum {
    RS_SAVE_IN_SAVES_FOLDER = 0, /* <ROM folder>/saves/ */
    RS_SAVE_NEXT_TO_ROM = 1,
    RS_SAVE_IN_TWLM_FOLDER = 2,  /* sd:/_nds/TWiLightMenu/saves/ */
} rs_save_location;

/* Which launcher's settings to read. */
typedef enum {
    RS_LAUNCHER_TWILIGHT,
    RS_LAUNCHER_FORWARDER,
} rs_launcher;

/* SAVE_LOCATION of a launcher (0 when unset or unknown). */
rs_save_location rs_twl_save_location(const char *sd_root, rs_launcher which);
/* SAVE_NUMBER of a ROM for a launcher (0 = the main ".sav"). */
int rs_twl_save_slot(const char *sd_root, rs_launcher which, const char *rom_path);
/* Save file of rom_path for a launcher. */
void rs_twl_save_path(const char *sd_root, rs_launcher which, const char *rom_path, char *out, size_t size);

/* Whether TWiLight Menu++ is installed (its settings or folder exist). */
bool rs_twl_installed(const char *sd_root);

/* "sdmc:/roms/nds/x.nds" -> "sd:/roms/nds/x.nds", the form the DS-mode
 * programs (forwarder, nds-bootstrap) expect. */
void rs_twl_ds_path(const char *sd_root, const char *path, char *out, size_t size);

/* Why the forwarder would use another save file than TWiLight Menu++ for
 * rom_path, in French with how to fix it, or "" when they agree. */
void rs_forwarder_mismatch(const char *sd_root, const char *rom_path, char *why, size_t size);

#endif
