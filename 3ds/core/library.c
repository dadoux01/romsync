/*
 * library.c - ROM scan and library entries (see library.h).
 */
#include "library.h"

#include <dirent.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/stat.h>

#include "twilight.h"

bool rs_is_rom_file(const char *name)
{
    return name[0] != '.' && (rs_str_ends_with_ci(name, ".nds") || rs_str_ends_with_ci(name, ".dsi") ||
                              rs_str_ends_with_ci(name, ".ids") || rs_str_ends_with_ci(name, ".srl"));
}

static void add_rom(rs_config *c, rs_scan_result *out, const char *path)
{
    struct stat st;
    if (stat(path, &st) != 0)
        return;
    rs_rom rom = {0};
    rs_strlcpy(rom.path, path, sizeof rom.path);
    rom.size = (long long)st.st_size;

    rs_nds_header h;
    rs_error err;
    const char *cached = rs_config_cached_id(c, path, rom.size);
    if (rs_rom_identify_header(path, &h, &err) != RS_OK) {
        if (!out->error[0])
            rs_strlcpy(out->error, err.message, sizeof out->error);
        return;
    }
    rs_strlcpy(rom.title, h.title, sizeof rom.title);
    if (rs_nds_has_valid_code(&h)) {
        rs_strlcpy(rom.detected_id, h.game_code, sizeof rom.detected_id);
    } else if (cached) {
        rs_strlcpy(rom.detected_id, cached, sizeof rom.detected_id);
    } else {
        /* Homebrew: SHA-1 of the whole file, then cached. */
        if (rs_rom_identify(path, &h, rom.detected_id, &err) != RS_OK) {
            if (!out->error[0])
                rs_strlcpy(out->error, err.message, sizeof out->error);
            return;
        }
        rs_config_cache_id(c, path, rom.size, rom.detected_id);
    }
    if (!rom.title[0])
        rs_strlcpy(rom.title, rs_basename(path), sizeof rom.title);

    rs_rom *roms = realloc(out->roms, (size_t)(out->count + 1) * sizeof *roms);
    if (!roms)
        return;
    out->roms = roms;
    out->roms[out->count++] = rom;
}

/* Scans dir; returns the number of ROMs found. */
static int scan_dir(rs_config *c, rs_scan_result *out, const char *dir, bool recursive, int depth)
{
    DIR *d = opendir(dir);
    if (!d) {
        if (!out->error[0])
            snprintf(out->error, sizeof out->error, "Dossier illisible : %s", dir);
        return 0;
    }
    /* Read the names first: the ROMs are opened after closedir, so that
     * only one directory handle is open at a time on the SD card. */
    char **names = NULL;
    bool *is_dir = NULL;
    int n = 0;
    struct dirent *e;
    while ((e = readdir(d)) != NULL) {
        if (e->d_name[0] == '.')
            continue;
        char path[RS_PATH_MAX];
        rs_path_join(path, sizeof path, dir, e->d_name);
        bool sub = rs_dir_exists(path);
        if (sub ? (!recursive || depth >= 8 || strcasecmp(e->d_name, "saves") == 0) : !rs_is_rom_file(e->d_name))
            continue;
        char **nn = realloc(names, (size_t)(n + 1) * sizeof *nn);
        bool *nd = realloc(is_dir, (size_t)(n + 1) * sizeof *nd);
        if (nn)
            names = nn;
        if (nd)
            is_dir = nd;
        if (!nn || !nd)
            break;
        names[n] = rs_strdup(e->d_name);
        is_dir[n++] = sub;
    }
    closedir(d);

    int found = 0;
    for (int i = 0; i < n; i++) {
        char path[RS_PATH_MAX];
        rs_path_join(path, sizeof path, dir, names[i]);
        if (is_dir[i]) {
            found += scan_dir(c, out, path, recursive, depth + 1);
        } else {
            int before = out->count;
            add_rom(c, out, path);
            found += out->count - before;
        }
        free(names[i]);
    }
    free(names);
    free(is_dir);
    return found;
}

static int compare_roms(const void *a, const void *b)
{
    const rs_rom *x = a, *y = b;
    int t = strcasecmp(x->title, y->title);
    return t ? t : strcmp(x->path, y->path);
}

void rs_scan(rs_config *c, rs_scan_result *out)
{
    memset(out, 0, sizeof *out);
    for (int i = 0; i < c->folder_count; i++)
        out->per_folder[i] = scan_dir(c, out, c->folders[i].path, c->folders[i].recursive, 0);
    if (out->count > 1)
        qsort(out->roms, (size_t)out->count, sizeof out->roms[0], compare_roms);
    /* The same ROM reached from two folders (a folder and its parent) is
     * kept once. */
    int k = 0;
    for (int i = 0; i < out->count; i++) {
        bool dup = false;
        for (int j = 0; j < k && !dup; j++)
            dup = strcmp(out->roms[j].path, out->roms[i].path) == 0;
        if (!dup)
            out->roms[k++] = out->roms[i];
    }
    out->count = k;
}

void rs_scan_free(rs_scan_result *r)
{
    free(r->roms);
    r->roms = NULL;
    r->count = 0;
}

void rs_build_library(const rs_scan_result *scan, const rs_config *c, const rs_state_store *states,
                      const rs_profile *profile, const char *sd_root, rs_library *out)
{
    out->count = 0;
    out->games = calloc(scan->count > 0 ? (size_t)scan->count : 1, sizeof *out->games);
    if (!out->games)
        return;
    for (int i = 0; i < scan->count; i++) {
        const rs_rom *r = &scan->roms[i];
        rs_game *g = &out->games[out->count++];
        rs_strlcpy(g->detected_id, r->detected_id, sizeof g->detected_id);
        for (int j = 0; j < scan->count; j++)
            g->shared_count += j != i && strcmp(scan->roms[j].detected_id, r->detected_id) == 0;

        /* ROMs sharing an identifier wait for the user's choice, ROM by ROM. */
        const rs_rom_choice *choice = g->shared_count ? rs_config_choice(c, r->path) : NULL;
        rs_entry *e = &g->entry;
        rs_strlcpy(e->rom_path, r->path, sizeof e->rom_path);
        rs_strlcpy(e->title, r->title, sizeof e->title);
        rs_strlcpy(e->game_id, choice && !choice->share ? choice->custom_id : r->detected_id, sizeof e->game_id);
        e->needs_choice = g->shared_count > 0 && !choice;
        e->profile = profile;
        rs_strlcpy(e->emulator, "twilight", sizeof e->emulator);
        if (!profile)
            rs_strlcpy(e->unavailable, "Profil de conversion « twilight » introuvable.", sizeof e->unavailable);

        g->slot = rs_twl_save_slot(sd_root, RS_LAUNCHER_TWILIGHT, r->path);
        if (rs_twl_save_location(sd_root, RS_LAUNCHER_TWILIGHT) == RS_SAVE_NEXT_TO_ROM)
            g->slot = 0;
        rs_twl_save_path(sd_root, RS_LAUNCHER_TWILIGHT, r->path, e->save_path, sizeof e->save_path);

        /* A save slot change is a change of save file, like an emulator
         * change on PC: an old file in the new slot is not sent blindly. */
        int previous = rs_config_slot(c, r->path);
        g->stale_after_slot_change = previous >= 0 && previous != g->slot && rs_is_stale_save(e, states);
    }
}

void rs_library_free(rs_library *l)
{
    free(l->games);
    l->games = NULL;
    l->count = 0;
}
