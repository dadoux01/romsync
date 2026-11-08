/*
 * app.c - actions of the 3DS app (see app.h).
 */
#include "app.h"

#include <3ds.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../core/platform.h"
#include "../core/twilight.h"
#include "browser.h"
#include "launch.h"
#include "ui.h"

#define TOKEN_FILE APP_DIR "/token.txt"

static rs_time engine_now(void *ctx)
{
    (void)ctx;
    return rs_platform_now();
}

/* ---- Start ------------------------------------------------------------- */

static void read_token(app *a)
{
    rs_buf b = {0};
    a->api.token[0] = 0;
    if (rs_read_file(TOKEN_FILE, &b, NULL) == RS_OK && rs_buf_terminate(&b)) {
        rs_strlcpy(a->api.token, (const char *)b.data, sizeof a->api.token);
        a->api.token[strcspn(a->api.token, "\r\n ")] = 0;
    }
    rs_buf_free(&b);
}

bool app_init(app *a)
{
    memset(a, 0, sizeof *a);
    rs_error err;
    rs_mkdirs(APP_DIR, NULL);
    if (rs_config_load(&a->config, APP_DIR "/config.json", &err) != RS_OK ||
        rs_state_open(&a->states, APP_DIR "/state.json", &err) != RS_OK ||
        rs_queue_open(&a->queue, APP_DIR "/queue", &err) != RS_OK) {
        ui_message("Erreur", err.message);
        return false;
    }
    /* Conversion profiles: the copies built into the app (romfs), replaced
     * by those of sd:/3ds/romsync/profiles/ when present. */
    if (rs_profiles_load_dir(&a->profiles, "romfs:/profiles", &err) != RS_OK) {
        ui_message("Erreur", err.message);
        return false;
    }
    if (rs_dir_exists(APP_DIR "/profiles") && rs_profiles_load_dir(&a->profiles, APP_DIR "/profiles", &err) != RS_OK)
        ui_message("Profils de la carte SD ignorés", err.message);
    a->twilight = rs_profiles_find(&a->profiles, "twilight");

    read_token(a);
    a->api.send = rs_http_curl_send;
    a->api.clock = &a->states.clock;
    a->api.now = engine_now;
    rs_strlcpy(a->api.base_url, a->config.server_url, sizeof a->api.base_url);
    a->engine = (rs_engine){.api = &a->api, .states = &a->states, .queue = &a->queue,
                            .keep_backups = a->config.keep_backups, .now = engine_now};

    const char *warning = a->config.warning[0] ? a->config.warning
                          : a->states.warning[0] ? a->states.warning
                                                 : a->queue.warning;
    if (warning[0])
        ui_message("Attention", warning);
    return true;
}

void app_exit(app *a)
{
    rs_state_save(&a->states, NULL); /* keeps the measured clock gap */
    free(a->views);
    rs_library_free(&a->lib);
    rs_scan_free(&a->scan);
    rs_profiles_free(&a->profiles);
    rs_queue_close(&a->queue);
    rs_state_close(&a->states);
    rs_config_free(&a->config);
}

/* ---- Pairing ----------------------------------------------------------- */

bool app_pair(app *a)
{
    char url[256], code[16] = "", name[64];
    rs_strlcpy(url, a->config.server_url[0] ? a->config.server_url : "http://", sizeof url);
    rs_strlcpy(name, a->config.device_name, sizeof name);

    for (;;) {
        ui_progress("Appairage",
                    "Sur le site de RomSync, clique « Ajouter un appareil » pour obtenir un code, puis saisis "
                    "l'adresse du serveur (ex. http://192.168.1.68:8085), le code et le nom de cette console.\n\n"
                    "Tailscale n'existe pas sur 3DS : le serveur doit être joignable sur le réseau local.");
        if (!ui_keyboard("Adresse du serveur", url, sizeof url, false) ||
            !ui_keyboard("Code d'appairage (ex. K7QM-4XPA)", code, sizeof code, false) ||
            !ui_keyboard("Nom de cet appareil", name, sizeof name, false)) {
            if (!ui_confirm("Appairage", "Appairage annulé.", "Recommencer", "Quitter"))
                return false;
            continue;
        }
        char normalized[256];
        if (!rs_api_normalize_url(url, normalized, sizeof normalized)) {
            ui_message("Adresse invalide", "Exemple d'adresse valide : http://192.168.1.68:8085");
            continue;
        }
        ui_progress("Appairage", "Connexion au serveur...");
        rs_strlcpy(a->api.base_url, normalized, sizeof a->api.base_url);
        a->api.token[0] = 0;
        char token[128];
        rs_error err;
        rs_status st = rs_api_pair(&a->api, code, name, "3ds", token, sizeof token, &err);
        if (st != RS_OK) {
            char msg[400];
            if (st == RS_ERR_API && err.http_status == 410)
                snprintf(msg, sizeof msg, "Code expiré ou déjà utilisé : génère un nouveau code sur le site.");
            else if (st == RS_ERR_API && err.http_status == 429)
                snprintf(msg, sizeof msg, "Trop d'essais : attends une minute.");
            else
                snprintf(msg, sizeof msg, "%s", err.message);
            ui_message("Appairage impossible", msg);
            continue;
        }
        /* The token is stored in clear on the SD card, as the spec says: a
         * stolen token is revoked from the site, without changing the
         * password. */
        if (rs_write_file_atomic(TOKEN_FILE, token, strlen(token), &err) != RS_OK) {
            ui_message("Erreur", err.message);
            return false;
        }
        rs_strlcpy(a->api.token, token, sizeof a->api.token);
        rs_strlcpy(a->config.server_url, normalized, sizeof a->config.server_url);
        rs_strlcpy(a->config.device_name, name, sizeof a->config.device_name);
        rs_config_save(&a->config, NULL);
        ui_message("Appairage réussi", "Cette console est maintenant reliée à ton compte RomSync.");
        return true;
    }
}

/* ---- ROM folders ------------------------------------------------------- */

static void add_folder(app *a, const char *start)
{
    char dir[RS_PATH_MAX];
    if (!browse_folder(start, dir, sizeof dir))
        return;
    bool recursive = ui_confirm("Sous-dossiers", "Chercher aussi les ROMs dans les sous-dossiers de ce dossier ?",
                                "Oui", "Non");
    if (!rs_config_add_folder(&a->config, dir, recursive))
        ui_message("Dossiers de ROMs", "Huit dossiers au plus.");
    rs_config_save(&a->config, NULL);
}

void app_choose_folders(app *a)
{
    if (a->config.folder_count == 0 && rs_dir_exists("sdmc:/roms/nds") &&
        ui_confirm("Dossiers de ROMs", "Le dossier sdmc:/roms/nds/ existe. L'utiliser comme dossier de ROMs ?",
                   "Oui", "Choisir un autre")) {
        bool recursive = ui_confirm("Sous-dossiers", "Chercher aussi les ROMs dans ses sous-dossiers ?", "Oui", "Non");
        rs_config_add_folder(&a->config, "sdmc:/roms/nds", recursive);
        rs_config_save(&a->config, NULL);
    }
    while (a->config.folder_count == 0) {
        ui_message("Dossiers de ROMs", "Choisis le dossier où sont tes ROMs DS.");
        add_folder(a, "sdmc:/");
    }
    while (a->config.folder_count < RS_MAX_FOLDERS &&
           ui_confirm("Dossiers de ROMs", "Ajouter un autre dossier de ROMs ?", "Oui", "Non"))
        add_folder(a, "sdmc:/");
}

void app_rescan(app *a)
{
    ui_progress("Recherche des ROMs", "Lecture des dossiers de ROMs...");
    free(a->views);
    a->views = NULL;
    rs_library_free(&a->lib);
    rs_scan_free(&a->scan);
    rs_scan(&a->config, &a->scan);
    rs_config_save(&a->config, NULL); /* homebrew identifiers cache */
    rs_build_library(&a->scan, &a->config, &a->states, a->twilight, SD_ROOT, &a->lib);
    a->views = calloc(a->lib.count > 0 ? (size_t)a->lib.count : 1, sizeof *a->views);
    for (int i = 0; i < a->lib.count; i++) {
        const rs_game *g = &a->lib.games[i];
        a->views[i].status = g->entry.needs_choice ? RS_STATUS_NEEDS_CHOICE : RS_STATUS_OFFLINE;
    }

    /* A folder without ROMs: say so instead of showing an empty list. */
    char msg[600] = "";
    for (int i = 0; i < a->config.folder_count; i++)
        if (a->scan.per_folder[i] == 0) {
            size_t n = strlen(msg);
            snprintf(msg + n, sizeof msg - n, "Aucune ROM DS (.nds) trouvée dans %s%s.\n",
                     a->config.folders[i].path, a->config.folders[i].recursive ? " ni ses sous-dossiers" : "");
        }
    if (a->scan.error[0]) {
        size_t n = strlen(msg);
        snprintf(msg + n, sizeof msg - n, "%s\n", a->scan.error);
    }
    if (msg[0])
        ui_message("Dossiers de ROMs", msg);
}

/* ---- Sync -------------------------------------------------------------- */

/* Asks what to do with an old save file found in a new save slot. Returns
 * the choice that applies to the sync: "send it anyway" is the user's
 * choice of the local save, not asked again as a divergence. */
static rs_choice handle_slot_change(app *a, rs_game *g)
{
    if (!g->stale_after_slot_change)
        return RS_CHOICE_NONE;
    rs_choice choice = RS_CHOICE_LOCAL;
    char text[600];
    snprintf(text, sizeof text,
             "%s utilise maintenant l'emplacement de save %d (%s). Ce fichier existe mais n'a jamais été "
             "synchronisé pour ce jeu : c'est sans doute une ancienne save.\n\n"
             "A : la mettre de côté dans .backup (la save du serveur sera téléchargée)\n"
             "B : l'envoyer quand même : elle deviendra la save active (l'autre reste dans l'historique)",
             g->entry.title, g->slot, rs_basename(g->entry.save_path));
    if (ui_confirm("Emplacement de save changé", text, "Mettre de côté", "Envoyer")) {
        char copy[RS_PATH_MAX];
        rs_error err;
        choice = RS_CHOICE_NONE;
        if (rs_set_aside(g->entry.save_path, rs_engine_now(&a->engine), a->config.keep_backups, copy, sizeof copy,
                         &err) != RS_OK)
            ui_message("Erreur", err.message);
    }
    g->stale_after_slot_change = false;
    return choice;
}

/* Two devices played without syncing: asks which save to keep. */
static rs_choice ask_divergence(app *a, const rs_game *g, const rs_divergence *d)
{
    /* The server's date in the console's time (the measured gap). */
    rs_time t = d->server.saved_at - (a->states.clock.known ? a->states.clock.offset : 0);
    char at[32], text[600];
    rs_time_format_iso(t, at, sizeof at);
    snprintf(text, sizeof text,
             "%s\n\n"
             "Deux appareils ont joué sans se synchroniser.\n"
             "- Serveur : save du %.10s à %.5s (%s).\n"
             "- Console : save modifiée depuis la dernière synchro, qui ne part pas de celle du serveur.\n\n"
             "Envoyer la tienne : elle devient la save active.\n"
             "Prendre celle du serveur : la tienne reste dans l'historique du site et dans .backup.\n"
             "Plus tard : rien n'est envoyé ni écrasé.",
             g->entry.title, at, at + 11, d->server.device_name[0] ? d->server.device_name : "site web");
    switch (ui_choose("Choix à faire", text, "envoyer ma save locale", "prendre celle du serveur", "plus tard")) {
    case 'A':
        return RS_CHOICE_LOCAL;
    case 'Y':
        return RS_CHOICE_SERVER;
    default:
        return RS_CHOICE_NONE;
    }
}

/* Syncs one game; *offline becomes true when the server cannot be reached
 * (the next games then only queue their changes). */
static void sync_game(app *a, int i, bool *offline)
{
    rs_game *g = &a->lib.games[i];
    game_view *v = &a->views[i];
    v->error = false;
    v->message[0] = 0;
    if (g->entry.needs_choice) {
        v->status = RS_STATUS_NEEDS_CHOICE;
        return;
    }
    v->choice_pending = false;
    rs_choice choice = handle_slot_change(a, g);

    rs_prepare_result r;
    rs_error err = {0};
    rs_status st = *offline ? rs_engine_offline_pass(&a->engine, &g->entry, &r, &err)
                            : rs_engine_prepare(&a->engine, &g->entry, 0, choice, &r, &err);
    if (st == RS_OK && r.needs_choice) {
        choice = ask_divergence(a, g, &r.divergence);
        if (choice == RS_CHOICE_NONE) {
            /* "Plus tard": asked again at the next start. */
            v->choice_pending = true;
            v->status = RS_STATUS_DIVERGED;
            rs_strlcpy(v->message, "Choix reporté : rien n'a été envoyé ni écrasé.", sizeof v->message);
            return;
        }
        st = rs_engine_prepare(&a->engine, &g->entry, 0, choice, &r, &err);
        if (st == RS_OK && r.needs_choice) { /* another device uploaded meanwhile */
            v->choice_pending = true;
            v->status = RS_STATUS_DIVERGED;
            rs_strlcpy(v->message, "Une autre save vient d'arriver : relance la synchronisation.", sizeof v->message);
            return;
        }
    }
    if (st != RS_OK) {
        v->error = true;
        v->status = g->entry.unavailable[0] ? RS_STATUS_UNAVAILABLE : RS_STATUS_TO_UPLOAD;
        rs_strlcpy(v->message, err.message, sizeof v->message);
        if (st == RS_ERR_REFUSED && strstr(err.message, "non autorisé"))
            *offline = true; /* no point in trying the next games */
        return;
    }
    rs_config_set_slot(&a->config, g->entry.rom_path, g->slot);
    v->synced = true;
    if (r.offline) {
        *offline = true;
        v->status = rs_queue_count_for(&a->queue, g->entry.save_path) ? RS_STATUS_TO_UPLOAD : RS_STATUS_OFFLINE;
    } else {
        v->status = rs_file_exists(g->entry.save_path) ? RS_STATUS_UP_TO_DATE : RS_STATUS_NO_SAVE;
        if (r.downloaded)
            rs_strlcpy(v->message, "Save du serveur téléchargée.", sizeof v->message);
        else if (r.uploaded)
            rs_strlcpy(v->message, "Save envoyée.", sizeof v->message);
    }
}

/* Reads the "conflit résolu automatiquement" flags of the server. */
static void read_conflicts(app *a)
{
    rs_remote_game *games;
    int n;
    if (rs_api_games(&a->api, &games, &n, NULL) != RS_OK)
        return;
    for (int i = 0; i < a->lib.count; i++)
        for (int k = 0; k < n; k++)
            if (strcmp(games[k].code, a->lib.games[i].entry.game_id) == 0)
                a->views[i].conflict = games[k].conflict;
    free(games);
}

/* Whether the Wi-Fi is connected (the "ac" service), to avoid waiting for
 * a network timeout when it is off. */
static bool wifi_connected(void)
{
    u32 status = 0;
    return R_SUCCEEDED(ACU_GetWifiStatus(&status)) && status != 0;
}

static void finish_sync(app *a, bool offline)
{
    a->online = !offline;
    if (a->online)
        read_conflicts(a);
    rs_config_save(&a->config, NULL);
    rs_state_save(&a->states, NULL);
    if (offline)
        snprintf(a->status_line, sizeof a->status_line, "Hors ligne : %d envoi(s) en attente", a->queue.count);
    else
        snprintf(a->status_line, sizeof a->status_line, "Synchronisé");
}

void app_sync_all(app *a)
{
    bool offline = !wifi_connected() || !a->api.token[0];
    if (!offline) {
        ui_progress("Synchronisation", "Envoi des saves en attente...");
        rs_flush_result f;
        rs_error err;
        if (rs_engine_flush(&a->engine, &f, &err) != RS_OK)
            ui_message("Erreur", err.message);
        else if (f.unauthorized)
            ui_message("Appareil non autorisé",
                       "Le serveur refuse cette console (appareil révoqué ?). Appaire-la de nouveau depuis les "
                       "réglages (SELECT).");
        offline = f.offline || f.unauthorized;
    }
    for (int i = 0; i < a->lib.count; i++) {
        char text[200];
        snprintf(text, sizeof text, "%s\n\n%d / %d", a->lib.games[i].entry.title, i + 1, a->lib.count);
        ui_progress(offline ? "Hors ligne : mise en file" : "Synchronisation", text);
        sync_game(a, i, &offline);
    }
    finish_sync(a, offline);
}

void app_sync_one(app *a, int index)
{
    if (index < 0 || index >= a->lib.count)
        return;
    bool offline = !wifi_connected() || !a->api.token[0];
    ui_progress("Synchronisation", a->lib.games[index].entry.title);
    sync_game(a, index, &offline);
    finish_sync(a, offline);
    if (a->views[index].error)
        ui_message("Synchronisation", a->views[index].message);
}

/* ---- Launch ------------------------------------------------------------ */

bool app_launch(app *a, int index)
{
    if (index < 0 || index >= a->lib.count)
        return false;
    rs_game *g = &a->lib.games[index];
    if (g->entry.needs_choice) {
        ui_message("Lancer", "Plusieurs ROMs partagent l'identifiant de ce jeu : choisis d'abord de partager ou "
                             "séparer leur save (Y).");
        return false;
    }
    char why[600];
    if (!launch_check(g->entry.rom_path, why, sizeof why)) {
        ui_message("Lancement impossible", why);
        return false;
    }

    /* Sync before launch (docs/SPEC.md, "Avant le lancement"). */
    bool offline = !wifi_connected() || !a->api.token[0];
    ui_progress("Avant le lancement", g->entry.title);
    sync_game(a, index, &offline);
    finish_sync(a, offline);
    game_view *v = &a->views[index];
    if (v->choice_pending)
        return false; /* "Plus tard": the game does not start */
    if (v->error && !ui_confirm("Synchronisation", v->message, "Lancer quand même", "Annuler"))
        return false;
    if (offline && !v->error)
        ui_message("Hors ligne", "Serveur injoignable : la partie se lance avec la save locale. Rouvre RomSync après "
                                 "avoir joué : ta save partira dès que le serveur répondra.");

    ui_progress("Lancement", "Démarrage du jeu...\n\nAprès la partie, rouvre RomSync pour envoyer ta save.");
    if (!launch_start(g->entry.rom_path, why, sizeof why)) {
        ui_message("Lancement impossible", why);
        return false;
    }
    return true;
}

/* ---- Shared identifiers ------------------------------------------------ */

void app_choose_sharing(app *a, int index)
{
    if (index < 0 || index >= a->lib.count || a->lib.games[index].shared_count == 0)
        return;
    rs_game *g = &a->lib.games[index];
    char text[500];
    snprintf(text, sizeof text,
             "%s partage l'identifiant %s avec %d autre(s) ROM(s) (variante, traduction, hack).\n\n"
             "A : partager la même save\n"
             "B : séparer (nouvel identifiant à nommer)",
             rs_basename(g->entry.rom_path), g->detected_id, g->shared_count);
    if (ui_confirm("Save partagée ?", text, "Partager", "Séparer")) {
        rs_config_set_choice(&a->config, g->entry.rom_path, true, NULL);
    } else {
        char name[40] = "";
        char id[RS_GAME_ID_MAX];
        if (!ui_keyboard("Nom de la save séparée (a-z, 0-9, -)", name, sizeof name, false))
            return;
        if (!rs_game_id_custom(name, id, sizeof id)) {
            ui_message("Nom invalide", "Lettres sans accents, chiffres, espaces ou tirets, 32 au plus.");
            return;
        }
        rs_config_set_choice(&a->config, g->entry.rom_path, false, id);
    }
    rs_config_save(&a->config, NULL);
    app_rescan(a);
}

/* ---- Settings ---------------------------------------------------------- */

static void manage_folders(app *a)
{
    int sel = 0;
    bool changed = false, redraw = true;
    while (aptMainLoop()) {
        if (redraw) {
            ui_top();
            ui_clear();
            ui_print(UI_CYAN "Dossiers de ROMs" UI_RESET "\n\n");
            for (int i = 0; i < a->config.folder_count; i++) {
                ui_print(i == sel ? UI_INVERSE "> " : "  ");
                char line[RS_PATH_MAX + 32];
                snprintf(line, sizeof line, "%s%s", a->config.folders[i].path,
                         a->config.folders[i].recursive ? " (+ sous-dossiers)" : "");
                ui_print_fit(line, UI_TOP_COLS - 3);
                ui_print(UI_RESET "\n");
            }
            ui_bottom();
            ui_clear();
            ui_print(UI_CYAN "Dossiers de ROMs" UI_RESET "\n\n");
            ui_print("A : sous-dossiers oui/non\nX : ajouter un dossier\nY : retirer ce dossier\nB : retour\n");
            redraw = false;
        }
        ui_frame();
        hidScanInput();
        u32 k = hidKeysDown();
        if (k & KEY_B)
            break;
        if ((k & KEY_DOWN) && sel + 1 < a->config.folder_count)
            sel++, redraw = true;
        if ((k & KEY_UP) && sel > 0)
            sel--, redraw = true;
        if ((k & KEY_A) && a->config.folder_count > 0) {
            a->config.folders[sel].recursive = !a->config.folders[sel].recursive;
            changed = redraw = true;
        }
        if (k & KEY_X) {
            add_folder(a, "sdmc:/");
            changed = redraw = true;
        }
        if ((k & KEY_Y) && a->config.folder_count > 1) {
            rs_config_remove_folder(&a->config, sel);
            if (sel >= a->config.folder_count)
                sel = a->config.folder_count - 1;
            changed = redraw = true;
        }
    }
    if (changed) {
        rs_config_save(&a->config, NULL);
        app_rescan(a);
    }
}

void app_settings(app *a)
{
    static const char *items[] = {"Dossiers de ROMs", "Copies .backup gardées par save", "Appairer de nouveau",
                                  "Retour"};
    int sel = 0;
    bool redraw = true;
    while (aptMainLoop()) {
        if (redraw) {
            ui_top();
            ui_clear();
            ui_print(UI_CYAN "Réglages" UI_RESET "\n\n");
            for (int i = 0; i < 4; i++) {
                ui_print(i == sel ? UI_INVERSE "> " : "  ");
                if (i == 1)
                    ui_print("%s : %d", items[i], a->config.keep_backups);
                else
                    ui_print("%s", items[i]);
                ui_print(UI_RESET "\n");
            }
            ui_print("\nServeur : %s\nAppareil : %s\n", a->config.server_url, a->config.device_name);
            ui_bottom();
            ui_clear();
            ui_print(UI_CYAN "Réglages" UI_RESET "\n\nA : choisir\nGauche/Droite : nombre de copies\nB : retour\n");
            redraw = false;
        }
        ui_frame();
        hidScanInput();
        u32 k = hidKeysDown();
        if (k & KEY_B)
            break;
        if ((k & KEY_DOWN) && sel < 3)
            sel++, redraw = true;
        if ((k & KEY_UP) && sel > 0)
            sel--, redraw = true;
        if (sel == 1 && (k & (KEY_LEFT | KEY_RIGHT))) {
            int n = a->config.keep_backups + ((k & KEY_RIGHT) ? 1 : -1);
            a->config.keep_backups = n < 1 ? 1 : n > 50 ? 50 : n;
            a->engine.keep_backups = a->config.keep_backups;
            rs_config_save(&a->config, NULL);
            redraw = true;
        }
        if (k & KEY_A) {
            if (sel == 0)
                manage_folders(a);
            else if (sel == 2)
                app_pair(a);
            else if (sel == 3)
                break;
            redraw = true;
        }
    }
}
