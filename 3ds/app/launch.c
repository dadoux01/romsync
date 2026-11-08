/*
 * launch.c - starting a DS game through a YANBF forwarder (see launch.h).
 */
#include "launch.h"

#include <3ds.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../core/rs.h"
#include "../core/twilight.h"
#include "app.h"

#define FORWARDER_DIR "sdmc:/_nds/ntr-forwarder"

typedef enum {
    TITLE_INSTALLED,
    TITLE_MISSING,
    TITLE_UNKNOWN, /* the "am" service cannot be used (e.g. from the Homebrew Launcher) */
} title_state;

/* Whether a title is installed on the NAND, from the list of the "am"
 * service (application manager). DSi-mode titles installed from a CIA live
 * there. rc receives the error code when the service cannot answer. */
static title_state title_installed(u64 tid, Result *rc)
{
    *rc = amInit();
    if (R_FAILED(*rc))
        return TITLE_UNKNOWN;
    title_state state = TITLE_UNKNOWN;
    u32 count = 0;
    *rc = AM_GetTitleCount(MEDIATYPE_NAND, &count);
    u64 *ids = R_SUCCEEDED(*rc) && count ? malloc(count * sizeof *ids) : NULL;
    if (ids) {
        u32 read = 0;
        *rc = AM_GetTitleList(&read, MEDIATYPE_NAND, count, ids);
        if (R_SUCCEEDED(*rc)) {
            state = TITLE_MISSING;
            for (u32 i = 0; i < read; i++)
                if (ids[i] == tid)
                    state = TITLE_INSTALLED;
        }
        free(ids);
    }
    amExit();
    return state;
}

bool launch_check(const char *rom_path, char *why, size_t size)
{
    why[0] = 0;
    /* Each missing piece gets its own message: "it does not work" is hard
     * to fix without knowing which part is missing. */
    if (!rs_file_exists(FORWARDER_DIR "/sdcard.nds")) {
        snprintf(why, size,
                 "sd:/_nds/ntr-forwarder/sdcard.nds est introuvable%s.\n\n"
                 "Dans le « DS Game Forwarder Pack » (github.com/RocketRobz/NTR_Forwarder, page Releases), copie "
                 "le contenu du dossier « for SD Card root » (le dossier _nds) à la racine de la carte SD, pas le "
                 "dossier lui-même.",
                 rs_dir_exists("sdmc:/for SD Card root") ? " (le dossier « for SD Card root » a été copié tel quel)"
                                                         : "");
        return false;
    }
    Result rc;
    title_state state = title_installed(YANBF_BOOTSTRAP_TID, &rc);
    if (state == TITLE_MISSING) {
        rs_strlcpy(why,
                   "bootstrap.cia de YANBF n'est pas installé.\n\n"
                   "Télécharge bootstrap.cia (github.com/YANBForwarder/YANBF, page Releases) et installe-le avec FBI.",
                   size);
        return false;
    }
    /* TITLE_UNKNOWN: the list of titles cannot be read (the .3dsx runs with
     * the services of the title hosting it). Do not block: the jump itself
     * tells whether bootstrap.cia is there. */
    /* The forwarder has its own save settings: if it would use another save
     * file than TWiLight Menu++, the synced save would not be the one the
     * game loads. Block the launch and explain how to align them. */
    rs_forwarder_mismatch(SD_ROOT, rom_path, why, size);
    return why[0] == 0;
}

bool launch_start(const char *rom_path, char *why, size_t size)
{
    if (!launch_check(rom_path, why, size))
        return false;

    /* path.txt holds the ROM path as the DS-mode programs see the SD card
     * ("sd:/roms/nds/Game.nds"), on one line without a line break: the
     * forwarder reads it with fgets and uses it as is. */
    char path[RS_PATH_MAX];
    rs_twl_ds_path(SD_ROOT, rom_path, path, sizeof path);
    rs_error err;
    if (rs_write_file_atomic(FORWARDER_DIR "/path.txt", path, strlen(path), &err) != RS_OK) {
        rs_strlcpy(why, err.message, size);
        return false;
    }

    /* Application jump (the "APT" applet manager): prepare the jump to the
     * DSi-mode title on the NAND, then hand over an empty parameter block.
     * The system starts bootstrap.cia once this app has exited. */
    Result rc = APT_PrepareToDoApplicationJump(0, YANBF_BOOTSTRAP_TID, MEDIATYPE_NAND);
    if (R_SUCCEEDED(rc)) {
        u8 param[0x300] = {0};
        u8 hmac[0x20] = {0};
        rc = APT_DoApplicationJump(param, sizeof param, hmac);
    }
    if (R_FAILED(rc)) {
        snprintf(why, size,
                 "Le système a refusé de lancer bootstrap.cia (erreur 0x%08lX). Vérifie qu'il est installé "
                 "(avec FBI), et installe RomSync en .cia : le lancement peut ne pas fonctionner depuis le "
                 "Homebrew Launcher.",
                 (unsigned long)rc);
        return false;
    }
    return true;
}
