/*
 * app.c - actions of the 3DS app (see app.h).
 */
#include "app.h"
#include "text.h"

#include <3ds.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../core/platform.h"
#include "../core/twilight.h"
#include "browser.h"
#include "launch.h"
#include "ui.h"
#include "updater.h"

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
    app_apply_language(a); /* the console's, until the settings are read */
    rs_error err;
    rs_mkdirs(APP_DIR, NULL);
    if (rs_config_load(&a->config, APP_DIR "/config.json", &err) != RS_OK ||
        rs_state_open(&a->states, APP_DIR "/state.json", &err) != RS_OK ||
        rs_queue_open(&a->queue, APP_DIR "/queue", &err) != RS_OK) {
        ui_message(RS_TR(ERROR), err.message);
        return false;
    }
    app_apply_language(a);
    /* Conversion profiles: the copies built into the app (romfs), replaced
     * by those of sd:/3ds/romsync/profiles/ when present. */
    if (rs_profiles_load_dir(&a->profiles, "romfs:/profiles", &err) != RS_OK) {
        ui_message(RS_TR(ERROR), err.message);
        return false;
    }
    if (rs_dir_exists(APP_DIR "/profiles") && rs_profiles_load_dir(&a->profiles, APP_DIR "/profiles", &err) != RS_OK)
        ui_message(RS_TR(SD_PROFILES_IGNORED), err.message);
    a->twilight = rs_profiles_find(&a->profiles, "twilight");
    a->tree = rs_profiles_find(&a->profiles, "tree");

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
        ui_message(RS_TR(WARNING), warning);
    return true;
}

void app_exit(app *a)
{
    rs_state_save(&a->states, NULL); /* keeps the measured clock gap */
    free(a->views);
    rs_library_free(&a->lib);
    titles_free(&a->titles);
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
        ui_progress(RS_TR(PAIRING), RS_TR(PAIRING_HELP));
        if (!ui_keyboard(RS_TR(SERVER_ADDRESS), url, sizeof url, false) ||
            !ui_keyboard(RS_TR(PAIRING_CODE), code, sizeof code, false) ||
            !ui_keyboard(RS_TR(DEVICE_NAME), name, sizeof name, false)) {
            if (!ui_confirm(RS_TR(PAIRING), RS_TR(PAIRING_CANCELLED), RS_TR(RETRY), RS_TR(QUIT)))
                return false;
            continue;
        }
        char normalized[256];
        if (!rs_api_normalize_url(url, normalized, sizeof normalized)) {
            ui_message(RS_TR(INVALID_ADDRESS), RS_TR(ADDRESS_EXAMPLE));
            continue;
        }
        ui_progress(RS_TR(PAIRING), RS_TR(CONNECTING));
        rs_strlcpy(a->api.base_url, normalized, sizeof a->api.base_url);
        a->api.token[0] = 0;
        char token[128];
        rs_error err;
        rs_status st = rs_api_pair(&a->api, code, name, "3ds", token, sizeof token, &err);
        if (st != RS_OK) {
            char msg[400];
            if (st == RS_ERR_API && err.http_status == 410)
                snprintf(msg, sizeof msg, RS_TR(CODE_EXPIRED));
            else if (st == RS_ERR_API && err.http_status == 429)
                snprintf(msg, sizeof msg, RS_TR(TOO_MANY_TRIES));
            else
                snprintf(msg, sizeof msg, "%s", err.message);
            ui_message(RS_TR(PAIRING_FAILED), msg);
            continue;
        }
        /* The token is stored in clear on the SD card, as the spec says: a
         * stolen token is revoked from the site, without changing the
         * password. */
        if (rs_write_file_atomic(TOKEN_FILE, token, strlen(token), &err) != RS_OK) {
            ui_message(RS_TR(ERROR), err.message);
            return false;
        }
        rs_strlcpy(a->api.token, token, sizeof a->api.token);
        rs_strlcpy(a->config.server_url, normalized, sizeof a->config.server_url);
        rs_strlcpy(a->config.device_name, name, sizeof a->config.device_name);
        rs_config_save(&a->config, NULL);
        ui_message(RS_TR(PAIRING_DONE), RS_TR(PAIRING_DONE_TEXT));
        return true;
    }
}

/* ---- ROM folders ------------------------------------------------------- */

static void add_folder(app *a, const char *start)
{
    char dir[RS_PATH_MAX];
    if (!browse_folder(start, dir, sizeof dir))
        return;
    bool recursive = ui_confirm(RS_TR(SUBFOLDERS), RS_TR(SUBFOLDERS_OF_THIS),
                                RS_TR(YES), RS_TR(NO));
    if (!rs_config_add_folder(&a->config, dir, recursive))
        ui_message(RS_TR(ROM_FOLDERS), RS_TR(EIGHT_FOLDERS_MAX));
    rs_config_save(&a->config, NULL);
}

void app_choose_folders(app *a)
{
    if (a->config.folder_count == 0 && rs_dir_exists("sdmc:/roms/nds") &&
        ui_confirm(RS_TR(ROM_FOLDERS), RS_TR(USE_ROMS_NDS),
                   RS_TR(YES), RS_TR(CHOOSE_ANOTHER))) {
        bool recursive = ui_confirm(RS_TR(SUBFOLDERS), RS_TR(SUBFOLDERS_OF_IT), RS_TR(YES), RS_TR(NO));
        rs_config_add_folder(&a->config, "sdmc:/roms/nds", recursive);
        rs_config_save(&a->config, NULL);
    }
    while (a->config.folder_count == 0) {
        ui_message(RS_TR(ROM_FOLDERS), RS_TR(CHOOSE_ROM_FOLDER));
        add_folder(a, "sdmc:/");
    }
    while (a->config.folder_count < RS_MAX_FOLDERS &&
           ui_confirm(RS_TR(ROM_FOLDERS), RS_TR(ADD_ANOTHER_FOLDER), RS_TR(YES), RS_TR(NO)))
        add_folder(a, "sdmc:/");
}

void app_rescan(app *a)
{
    ui_progress(RS_TR(SCANNING), RS_TR(READING_FOLDERS));
    free(a->views);
    a->views = NULL;
    rs_library_free(&a->lib);
    rs_scan_free(&a->scan);
    rs_scan(&a->config, &a->scan);
    rs_config_save(&a->config, NULL); /* homebrew identifiers cache */
    rs_build_library(&a->scan, &a->config, &a->states, a->twilight, SD_ROOT, &a->lib);
    /* The 3DS games of the console, after the DS ROMs. */
    titles_free(&a->titles);
    titles_list(&a->titles);
    titles_add_to_library(&a->titles, a->tree, CTR_BACKUP_DIR, &a->lib);
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
            if (a->config.folders[i].recursive)
                snprintf(msg + n, sizeof msg - n, RS_TR(NO_ROM_IN_TREE), a->config.folders[i].path);
            else
                snprintf(msg + n, sizeof msg - n, RS_TR(NO_ROM_IN), a->config.folders[i].path);
        }
    if (a->scan.error[0]) {
        size_t n = strlen(msg);
        snprintf(msg + n, sizeof msg - n, "%s\n", a->scan.error);
    }
    if (a->titles.error[0]) {
        size_t n = strlen(msg);
        snprintf(msg + n, sizeof msg - n, "%s\n", a->titles.error);
    }
    if (msg[0])
        ui_message(RS_TR(ROM_FOLDERS), msg);
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
    snprintf(text, sizeof text, RS_TR(SLOT_CHANGED_TEXT), g->entry.title, g->slot, rs_basename(g->entry.save_path));
    if (ui_confirm(RS_TR(SLOT_CHANGED), text, RS_TR(SET_ASIDE), RS_TR(SEND))) {
        char copy[RS_PATH_MAX];
        rs_error err;
        choice = RS_CHOICE_NONE;
        if (rs_set_aside(g->entry.save_path, rs_engine_now(&a->engine), a->config.keep_backups, copy, sizeof copy,
                         &err) != RS_OK)
            ui_message(RS_TR(ERROR), err.message);
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
    snprintf(text, sizeof text, RS_TR(DIVERGENCE_TEXT), g->entry.title, at, at + 11, d->server.device_name[0] ? d->server.device_name : RS_TR(WEBSITE));
    switch (ui_choose(RS_TR(CHOICE_NEEDED), text, RS_TR(SEND_MY_SAVE), RS_TR(TAKE_SERVER), RS_TR(LATER))) {
    case 'A':
        return RS_CHOICE_LOCAL;
    case 'Y':
        return RS_CHOICE_SERVER;
    default:
        return RS_CHOICE_NONE;
    }
}

/* Whether the game has a save on the console. */
static bool has_local_save(const rs_game *g)
{
    const ctr_title *t = titles_of_entry(&g->entry);
    return t ? t->has_save : rs_file_exists(g->entry.save_path);
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
    bool asked = false; /* the user just chose after a divergence */
    rs_status st = *offline ? rs_engine_offline_pass(&a->engine, &g->entry, &r, &err)
                            : rs_engine_prepare(&a->engine, &g->entry, 0, choice, &r, &err);
    if (st == RS_OK && r.needs_choice) {
        choice = ask_divergence(a, g, &r.divergence);
        if (choice == RS_CHOICE_NONE) {
            /* "Plus tard": asked again at the next start. */
            v->choice_pending = true;
            v->status = RS_STATUS_DIVERGED;
            rs_strlcpy(v->message, RS_TR(CHOICE_POSTPONED), sizeof v->message);
            return;
        }
        /* Uploading then downloading takes a while: say what happens
         * instead of leaving the question on screen. */
        asked = true;
        ui_progress(RS_TR(CHOICE_NEEDED),
                    choice == RS_CHOICE_SERVER ? RS_TR(TAKING_SERVER_SAVE) : RS_TR(SENDING_LOCAL_SAVE));
        st = rs_engine_prepare(&a->engine, &g->entry, 0, choice, &r, &err);
        if (st == RS_OK && r.needs_choice) { /* another device uploaded meanwhile */
            v->choice_pending = true;
            v->status = RS_STATUS_DIVERGED;
            rs_strlcpy(v->message, RS_TR(ANOTHER_SAVE_ARRIVED), sizeof v->message);
            return;
        }
    }
    if (st != RS_OK) {
        v->error = true;
        v->status = g->entry.unavailable[0] ? RS_STATUS_UNAVAILABLE : RS_STATUS_TO_UPLOAD;
        rs_strlcpy(v->message, err.message, sizeof v->message);
        if (st == RS_ERR_REFUSED && strcmp(err.code, "unauthorized") == 0)
            *offline = true; /* no point in trying the next games */
        return;
    }
    if (!titles_of_entry(&g->entry))
        rs_config_set_slot(&a->config, g->entry.rom_path, g->slot);
    v->synced = true;
    if (r.offline) {
        *offline = true;
        v->status = rs_queue_count_for(&a->queue, g->entry.save_path) ? RS_STATUS_TO_UPLOAD : RS_STATUS_OFFLINE;
    } else {
        v->status = has_local_save(g) ? RS_STATUS_UP_TO_DATE : RS_STATUS_NO_SAVE;
        if (asked)
            rs_strlcpy(v->message, choice == RS_CHOICE_SERVER ? RS_TR(SERVER_SAVE_TAKEN) : RS_TR(LOCAL_SAVE_SENT),
                       sizeof v->message);
        else if (r.downloaded)
            rs_strlcpy(v->message, RS_TR(DOWNLOADED), sizeof v->message);
        else if (r.uploaded)
            rs_strlcpy(v->message, RS_TR(UPLOADED), sizeof v->message);
        if (asked)
            ui_message(RS_TR(CHOICE_NEEDED), v->message);
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
        snprintf(a->status_line, sizeof a->status_line, RS_TR(OFFLINE_QUEUED), a->queue.count);
    else
        snprintf(a->status_line, sizeof a->status_line, RS_TR(SYNCED));
}

void app_sync_all(app *a)
{
    bool offline = !wifi_connected() || !a->api.token[0];
    if (!offline) {
        ui_progress(RS_TR(SYNC), RS_TR(SENDING_QUEUE));
        rs_flush_result f;
        rs_error err;
        if (rs_engine_flush(&a->engine, &f, &err) != RS_OK)
            ui_message(RS_TR(ERROR), err.message);
        else if (f.unauthorized)
            ui_message(RS_TR(UNAUTHORIZED), RS_TR(UNAUTHORIZED_TEXT));
        offline = f.offline || f.unauthorized;
    }
    for (int i = 0; i < a->lib.count; i++) {
        char text[200];
        snprintf(text, sizeof text, "%s\n\n%d / %d", a->lib.games[i].entry.title, i + 1, a->lib.count);
        ui_progress(offline ? RS_TR(OFFLINE_QUEUING) : RS_TR(SYNC), text);
        sync_game(a, i, &offline);
    }
    finish_sync(a, offline);
}

void app_sync_one(app *a, int index)
{
    if (index < 0 || index >= a->lib.count)
        return;
    bool offline = !wifi_connected() || !a->api.token[0];
    ui_progress(RS_TR(SYNC), a->lib.games[index].entry.title);
    sync_game(a, index, &offline);
    finish_sync(a, offline);
    if (a->views[index].error)
        ui_message(RS_TR(SYNC), a->views[index].message);
}

/* ---- Launch ------------------------------------------------------------ */

bool app_launch(app *a, int index)
{
    if (index < 0 || index >= a->lib.count)
        return false;
    rs_game *g = &a->lib.games[index];
    if (g->entry.needs_choice) {
        ui_message(RS_TR(LAUNCH), RS_TR(LAUNCH_SHARED_ID));
        return false;
    }
    char why[600];
    const ctr_title *title = titles_of_entry(&g->entry);
    if (!title && !launch_check(g->entry.rom_path, why, sizeof why)) {
        ui_message(RS_TR(LAUNCH_FAILED), why);
        return false;
    }

    /* Sync before launch (docs/SPEC.md, RS_TR(BEFORE_LAUNCH)). */
    bool offline = !wifi_connected() || !a->api.token[0];
    ui_progress(RS_TR(BEFORE_LAUNCH), g->entry.title);
    sync_game(a, index, &offline);
    finish_sync(a, offline);
    game_view *v = &a->views[index];
    if (v->choice_pending)
        return false; /* "Later": the game does not start */
    if (v->error && !ui_confirm(RS_TR(SYNC), v->message, RS_TR(LAUNCH_ANYWAY), RS_TR(CANCEL)))
        return false;
    if (offline && !v->error)
        ui_message(RS_TR(OFFLINE), RS_TR(OFFLINE_LAUNCH));

    ui_progress(RS_TR(LAUNCHING), RS_TR(STARTING_GAME));
    if (title ? !titles_launch(title, why, sizeof why) : !launch_start(g->entry.rom_path, why, sizeof why)) {
        ui_message(RS_TR(LAUNCH_FAILED), why);
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
    snprintf(text, sizeof text, RS_TR(SHARING_TEXT), rs_basename(g->entry.rom_path), g->detected_id, g->shared_count);
    if (ui_confirm(RS_TR(SHARED_SAVE), text, RS_TR(SHARE), RS_TR(SEPARATE))) {
        rs_config_set_choice(&a->config, g->entry.rom_path, true, NULL);
    } else {
        char name[40] = "";
        char id[RS_GAME_ID_MAX];
        if (!ui_keyboard(RS_TR(SEPARATE_NAME), name, sizeof name, false))
            return;
        if (!rs_game_id_custom(name, id, sizeof id)) {
            ui_message(RS_TR(INVALID_NAME), RS_TR(INVALID_NAME_TEXT));
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
            ui_print(UI_CYAN "%s" UI_RESET "\n\n", RS_TR(ROM_FOLDERS));
            for (int i = 0; i < a->config.folder_count; i++) {
                ui_print(i == sel ? UI_INVERSE "> " : "  ");
                char line[RS_PATH_MAX + 32];
                snprintf(line, sizeof line, "%s%s", a->config.folders[i].path,
                         a->config.folders[i].recursive ? RS_TR(WITH_SUBFOLDERS) : "");
                ui_print_fit(line, UI_TOP_COLS - 3);
                ui_print(UI_RESET "\n");
            }
            ui_bottom();
            ui_clear();
            ui_print(UI_CYAN "%s" UI_RESET "\n\n%s", RS_TR(ROM_FOLDERS), RS_TR(FOLDERS_KEYS));
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

/* Language of the texts: the one chosen in the settings, else the
 * console's (docs/SPEC.md, "Langues"). */
void app_apply_language(const app *a)
{
    if (a->config.language[0]) {
        rs_set_language(rs_lang_from_code(a->config.language));
        return;
    }
    u8 lang = CFG_LANGUAGE_EN;
    if (R_SUCCEEDED(cfguInit())) {
        CFGU_GetSystemLanguage(&lang);
        cfguExit();
    }
    rs_set_language(lang == CFG_LANGUAGE_FR ? RS_LANG_FR : RS_LANG_EN);
}

/* Console, then each language: the setting of the "Langue" line. */
static const char *const languages[] = {"", "fr", "en"};
enum { N_LANGUAGES = 3 };

static const char *language_name(const char *code)
{
    return strcmp(code, "fr") == 0 ? "Français" : strcmp(code, "en") == 0 ? "English" : RS_TR(LANGUAGE_SYSTEM);
}

static void next_language(app *a, int step)
{
    int i = 0;
    while (i < N_LANGUAGES && strcmp(languages[i], a->config.language) != 0)
        i++;
    i = ((i < N_LANGUAGES ? i : 0) + step + N_LANGUAGES) % N_LANGUAGES;
    rs_strlcpy(a->config.language, languages[i], sizeof a->config.language);
    rs_config_save(&a->config, NULL);
    app_apply_language(a);
}

bool app_settings(app *a)
{
    enum { ITEM_FOLDERS, ITEM_LANGUAGE, ITEM_BACKUPS, ITEM_AUTO_UPDATE, ITEM_CHECK_NOW, ITEM_PAIR, ITEM_BACK, N_ITEMS };
    int sel = 0;
    bool redraw = true;
    while (aptMainLoop()) {
        if (redraw) {
            /* Built at each drawing: the language may have just changed. */
            const char *items[N_ITEMS] = {RS_TR(ROM_FOLDERS),       RS_TR(SETTING_LANGUAGE),  RS_TR(SETTING_BACKUPS),
                                          RS_TR(SETTING_AUTO_UPDATE), RS_TR(SETTING_CHECK_NOW), RS_TR(SETTING_PAIR_AGAIN),
                                          RS_TR(BACK)};
            ui_top();
            ui_clear();
            ui_print(UI_CYAN "%s" UI_RESET "\n\n", RS_TR(SETTINGS));
            for (int i = 0; i < N_ITEMS; i++) {
                ui_print(i == sel ? UI_INVERSE "> " : "  ");
                if (i == ITEM_LANGUAGE)
                    ui_print("%s : %s", items[i], language_name(a->config.language));
                else if (i == ITEM_BACKUPS)
                    ui_print("%s : %d", items[i], a->config.keep_backups);
                else if (i == ITEM_AUTO_UPDATE)
                    ui_print("%s : %s", items[i], a->config.check_updates ? RS_TR(YES_LOWER) : RS_TR(NO_LOWER));
                else
                    ui_print("%s", items[i]);
                ui_print(UI_RESET "\n");
            }
            ui_print(RS_TR(SETTINGS_INFO), a->config.server_url, a->config.device_name, RS_VERSION);
            ui_bottom();
            ui_clear();
            ui_print(UI_CYAN "%s" UI_RESET "%s", RS_TR(SETTINGS), RS_TR(SETTINGS_KEYS));
            redraw = false;
        }
        ui_frame();
        hidScanInput();
        u32 k = hidKeysDown();
        if (k & KEY_B)
            break;
        if ((k & KEY_DOWN) && sel < N_ITEMS - 1)
            sel++, redraw = true;
        if ((k & KEY_UP) && sel > 0)
            sel--, redraw = true;
        if (sel == ITEM_LANGUAGE && (k & (KEY_A | KEY_LEFT | KEY_RIGHT))) {
            next_language(a, (k & KEY_LEFT) ? -1 : 1);
            redraw = true;
            continue;
        }
        if (sel == ITEM_BACKUPS && (k & (KEY_LEFT | KEY_RIGHT))) {
            int n = a->config.keep_backups + ((k & KEY_RIGHT) ? 1 : -1);
            a->config.keep_backups = n < 1 ? 1 : n > 50 ? 50 : n;
            a->engine.keep_backups = a->config.keep_backups;
            rs_config_save(&a->config, NULL);
            redraw = true;
        }
        if (sel == ITEM_AUTO_UPDATE && (k & (KEY_A | KEY_LEFT | KEY_RIGHT))) {
            a->config.check_updates = !a->config.check_updates;
            rs_config_save(&a->config, NULL);
            redraw = true;
            continue;
        }
        if (k & KEY_A) {
            if (sel == ITEM_FOLDERS)
                manage_folders(a);
            else if (sel == ITEM_CHECK_NOW && app_check_update(a, true))
                return true;
            else if (sel == ITEM_PAIR)
                app_pair(a);
            else if (sel == ITEM_BACK)
                break;
            redraw = true;
        }
    }
    return false;
}
