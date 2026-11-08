/*
 * main.c - RomSync for the 3DS: starts the system services, runs the first
 * start (pairing, ROM folders), syncs every save, then shows the game list.
 *
 * Top screen: the games and the state of their save.
 * Bottom screen: details of the selected game and the keys.
 */
#include <3ds.h>
#include <curl/curl.h>
#include <malloc.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "../core/twilight.h"
#include "app.h"
#include "ui.h"
#include "updater.h"

#define LIST_ROWS (UI_ROWS - 3)

/* The network stack (soc:U) needs a buffer it owns for the whole run,
 * aligned on 4 KiB. 1 MiB is the usual size for curl. */
#define SOC_BUFFER_SIZE 0x100000
static u32 *soc_buffer;

/* Stack of the main thread. libctru carves it out of the start of the heap
 * (system/stack_adjust.s) and gives it 32 KiB by default: too little for
 * curl and the file helpers, and an overflow writes below 0x08000000,
 * where nothing is mapped (data abort). 256 KiB leaves plenty of room. */
u32 __stacksize__ = 256 * 1024;

/* The app state is large (settings, profiles): keep it off the stack. */
static app a;

static const char *status_color(rs_save_status s, bool error)
{
    if (error)
        return UI_RED;
    switch (s) {
    case RS_STATUS_UP_TO_DATE:
        return UI_GREEN;
    case RS_STATUS_TO_UPLOAD:
    case RS_STATUS_TO_DOWNLOAD:
        return UI_YELLOW;
    case RS_STATUS_NEEDS_CHOICE:
    case RS_STATUS_UNAVAILABLE:
    case RS_STATUS_DIVERGED:
        return UI_RED;
    default:
        return UI_WHITE;
    }
}

static void draw_list(const app *a, int sel, int scroll)
{
    ui_top();
    ui_clear();
    char header[128];
    snprintf(header, sizeof header, "RomSync - %s - %s", a->config.device_name, a->status_line);
    ui_print(UI_CYAN);
    ui_print_fit(header, UI_TOP_COLS);
    ui_print(UI_RESET);
    if (a->lib.count == 0)
        ui_print("\nAucune ROM DS trouvée.\nSELECT : réglages, pour choisir les dossiers.\n");
    for (int i = scroll; i < a->lib.count && i < scroll + LIST_ROWS; i++) {
        const rs_game *g = &a->lib.games[i];
        const game_view *v = &a->views[i];
        char label[24];
        snprintf(label, sizeof label, "%s%s", v->error ? "erreur" : rs_status_label(v->status),
                 v->conflict ? "*" : "");
        ui_print(i == sel ? UI_INVERSE "> " : "  ");
        ui_print_fit(g->entry.title, 30);
        ui_print(" %s", status_color(v->status, v->error));
        ui_print_fit(label, 16);
        ui_print(UI_RESET "\n");
    }
    ui_move(UI_ROWS - 1, 0);
    ui_print("* conflit résolu automatiquement");
}

static void draw_details(const app *a, int sel)
{
    ui_bottom();
    ui_clear();
    if (sel < a->lib.count) {
        const rs_game *g = &a->lib.games[sel];
        const game_view *v = &a->views[sel];
        const rs_save_state *s = rs_state_for(&a->states, g->entry.save_path, g->entry.game_id);
        ui_print(UI_CYAN);
        ui_print_fit(g->entry.title, UI_BOTTOM_COLS);
        ui_print(UI_RESET);
        ui_print("Identifiant : %s\n", g->entry.game_id);
        ui_print("ROM : ");
        ui_print_fit(rs_basename(g->entry.rom_path), UI_BOTTOM_COLS - 7);
        ui_print("\nSave : ");
        ui_print_fit(rs_basename(g->entry.save_path), UI_BOTTOM_COLS - 8);
        ui_print("\nEmplacement de save : %d%s\n", g->slot, g->slot ? "" : " (.sav)");
        ui_print("État : %s%s" UI_RESET "\n", status_color(v->status, v->error), rs_status_label(v->status));
        if (s) {
            char at[32];
            rs_time_format_iso(s->synced_at, at, sizeof at);
            ui_print("Dernière synchro : %.10s %.5s\n", at, at + 11);
        }
        int pending = rs_queue_count_for(&a->queue, g->entry.save_path);
        if (pending)
            ui_print(UI_YELLOW "%d envoi(s) en attente" UI_RESET "\n", pending);
        if (v->choice_pending)
            ui_print(UI_RED "Choix à faire : deux appareils ont\njoué sans se synchroniser (A)." UI_RESET "\n");
        else if (v->conflict)
            ui_print(UI_YELLOW "Divergence : voir l'historique\nsur le site." UI_RESET "\n");
        if (g->shared_count)
            ui_print("Partage l'identifiant %s\navec %d autre(s) ROM(s).\n", g->detected_id, g->shared_count);
        if (v->message[0]) {
            ui_print("\n");
            ui_print_wrapped(v->message, UI_BOTTOM_COLS);
        }
    }
    ui_move(UI_ROWS - 5, 0);
    ui_print("A : synchroniser ce jeu   R : tout\n");
    ui_print("X : lancer");
    if (sel < a->lib.count && a->lib.games[sel].shared_count)
        ui_print("   Y : partager/séparer");
    ui_print("\nSELECT : réglages   START : quitter\n");
}

int main(void)
{
    ui_init();
    romfsInit();
    psInit();
    acInit();
    soc_buffer = memalign(0x1000, SOC_BUFFER_SIZE);
    bool network = soc_buffer && R_SUCCEEDED(socInit(soc_buffer, SOC_BUFFER_SIZE));
    curl_global_init(CURL_GLOBAL_DEFAULT);
    srand((unsigned)time(NULL));

    bool ok = app_init(&a);
    if (ok && !network)
        ui_message("Réseau", "Le service réseau n'a pas démarré : RomSync fonctionnera hors ligne.");
    if (ok && !a.twilight)
        ui_message("Profil manquant", "Le profil de conversion « twilight » est introuvable : réinstalle RomSync.");

    /* First start: pairing, then ROM folders. */
    if (ok && (!a.api.token[0] || !a.config.server_url[0]))
        ok = app_pair(&a);
    if (ok && a.config.folder_count == 0)
        app_choose_folders(&a);
    if (ok && !rs_twl_installed(SD_ROOT))
        ui_message("TWiLight Menu++",
                   "sd:/_nds/TWiLightMenu/ est introuvable : RomSync suppose les réglages par défaut (saves dans "
                   "le dossier saves/ de chaque dossier de ROMs).");
    bool updated = false;
    if (ok) {
        app_rescan(&a);
        app_sync_all(&a); /* uploads first, then downloads */
        app_check_compatibility(&a);
        if (a.config.check_updates)
            updated = app_check_update(&a, false);
    }

    int sel = 0, scroll = 0;
    bool redraw = true;
    while (ok && !updated && aptMainLoop()) {
        if (redraw) {
            draw_list(&a, sel, scroll);
            draw_details(&a, sel);
            redraw = false;
        }
        ui_frame();
        hidScanInput();
        u32 k = hidKeysDown();
        if (k & KEY_START)
            break;
        if ((k & KEY_DOWN) && sel + 1 < a.lib.count)
            sel++, redraw = true;
        if ((k & KEY_UP) && sel > 0)
            sel--, redraw = true;
        if ((k & KEY_RIGHT) && a.lib.count) /* page down */
            sel = sel + LIST_ROWS < a.lib.count ? sel + LIST_ROWS : a.lib.count - 1, redraw = true;
        if (k & KEY_LEFT) /* page up */
            sel = sel > LIST_ROWS ? sel - LIST_ROWS : 0, redraw = true;
        if (k & KEY_A) {
            app_sync_one(&a, sel);
            redraw = true;
        }
        if (k & KEY_R) {
            app_sync_all(&a);
            redraw = true;
        }
        if (k & KEY_Y) {
            app_choose_sharing(&a, sel);
            redraw = true;
        }
        if (k & KEY_X) {
            /* On success the jump to the game happens when RomSync exits. */
            if (app_launch(&a, sel))
                break;
            redraw = true;
        }
        if (k & KEY_SELECT) {
            if (app_settings(&a))
                break; /* a new version was installed */
            redraw = true;
        }
        if (sel >= a.lib.count)
            sel = a.lib.count ? a.lib.count - 1 : 0;
        if (sel < scroll)
            scroll = sel;
        if (sel >= scroll + LIST_ROWS)
            scroll = sel - LIST_ROWS + 1;
    }

    app_exit(&a);
    curl_global_cleanup();
    if (network)
        socExit();
    free(soc_buffer);
    acExit();
    psExit();
    romfsExit();
    gfxExit();
    return 0;
}
