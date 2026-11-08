/*
 * launch.c - starting a DS game through a YANBF forwarder (see launch.h).
 */
#include "launch.h"

#include <3ds.h>
#include <stdio.h>
#include <string.h>

#include "../core/rs.h"
#include "../core/twilight.h"
#include "app.h"

#define FORWARDER_DIR "sdmc:/_nds/ntr-forwarder"

static const char *install_help =
    "Pour lancer un jeu depuis RomSync, installe :\n"
    "1. bootstrap.cia de YANBF (github.com/YANBForwarder/YANBF, page Releases), avec FBI ;\n"
    "2. le « DS Game Forwarder Pack » (github.com/RocketRobz/NTR_Forwarder, page Releases) : copie le "
    "contenu de « for SD card root » à la racine de la carte SD.\n\n"
    "Sans eux, lance tes jeux depuis TWiLight Menu++ puis rouvre RomSync pour envoyer ta save.";

/* Whether a title is installed on the NAND (the "am" service, application
 * manager). DSi-mode titles installed from a CIA live there. */
static bool title_installed(u64 tid)
{
    if (R_FAILED(amInit()))
        return false;
    AM_TitleInfo info;
    bool found = R_SUCCEEDED(AM_GetTitleInfo(MEDIATYPE_NAND, 1, &tid, &info));
    amExit();
    return found;
}

bool launch_check(const char *rom_path, char *why, size_t size)
{
    why[0] = 0;
    if (!title_installed(YANBF_BOOTSTRAP_TID) || !rs_file_exists(FORWARDER_DIR "/sdcard.nds")) {
        rs_strlcpy(why, install_help, size);
        return false;
    }
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
                 "Le système a refusé de lancer bootstrap.cia (erreur 0x%08lX). Installe RomSync en .cia : "
                 "le lancement peut ne pas fonctionner depuis le Homebrew Launcher.",
                 (unsigned long)rc);
        return false;
    }
    return true;
}
