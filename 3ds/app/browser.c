/*
 * browser.c - SD card folder browser (see browser.h).
 *
 * Top screen: the sub-folders of the current folder, and how many DS ROMs
 * it holds directly. Bottom screen: the keys.
 */
#include "browser.h"

#include <3ds.h>
#include <dirent.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

#include "../core/library.h"
#include "../core/rs.h"
#include "ui.h"

#define MAX_ENTRIES 256
#define LIST_ROWS (UI_ROWS - 4)

typedef struct {
    char *names[MAX_ENTRIES];
    int count;
    int roms; /* DS ROMs directly in the folder */
} listing;

static int compare(const void *a, const void *b)
{
    return strcasecmp(*(char *const *)a, *(char *const *)b);
}

static void list_folder(const char *dir, listing *l)
{
    memset(l, 0, sizeof *l);
    DIR *d = opendir(dir);
    if (!d)
        return;
    struct dirent *e;
    while ((e = readdir(d)) != NULL) {
        if (e->d_name[0] == '.')
            continue;
        if (rs_is_rom_file(e->d_name)) {
            l->roms++;
            continue;
        }
        char path[RS_PATH_MAX];
        rs_path_join(path, sizeof path, dir, e->d_name);
        if (l->count < MAX_ENTRIES && rs_dir_exists(path))
            l->names[l->count++] = rs_strdup(e->d_name);
    }
    closedir(d);
    qsort(l->names, (size_t)l->count, sizeof l->names[0], compare);
}

static void free_listing(listing *l)
{
    for (int i = 0; i < l->count; i++)
        free(l->names[i]);
    l->count = 0;
}

static void draw(const char *dir, const listing *l, int sel, int scroll)
{
    ui_top();
    ui_clear();
    ui_print(UI_CYAN);
    ui_print_fit(dir, UI_TOP_COLS);
    ui_print(UI_RESET);
    ui_print("%d ROM(s) DS dans ce dossier\n\n", l->roms);
    if (l->count == 0)
        ui_print("(aucun sous-dossier)\n");
    for (int i = scroll; i < l->count && i < scroll + LIST_ROWS; i++) {
        ui_print(i == sel ? UI_INVERSE "> " : "  ");
        ui_print_fit(l->names[i], UI_TOP_COLS - 3);
        ui_print(UI_RESET "\n");
    }

    ui_bottom();
    ui_clear();
    ui_print(UI_CYAN "Choisir un dossier de ROMs" UI_RESET "\n\n");
    ui_print("Haut/Bas : se déplacer\n");
    ui_print("A        : ouvrir le dossier\n");
    ui_print("B        : dossier parent\n");
    ui_print("X        : choisir ce dossier\n");
    ui_print("START    : annuler\n");
}

bool browse_folder(const char *start, char *out, size_t size)
{
    char dir[RS_PATH_MAX];
    rs_strlcpy(dir, start && start[0] ? start : "sdmc:/", sizeof dir);
    listing l;
    list_folder(dir, &l);
    int sel = 0, scroll = 0;
    bool redraw = true, chosen = false;

    while (aptMainLoop()) {
        if (redraw) {
            draw(dir, &l, sel, scroll);
            redraw = false;
        }
        ui_frame();
        hidScanInput();
        u32 k = hidKeysDown();
        if (k & KEY_START)
            break;
        if ((k & KEY_DOWN) && sel + 1 < l.count)
            sel++, redraw = true;
        if ((k & KEY_UP) && sel > 0)
            sel--, redraw = true;
        if (k & KEY_X) {
            rs_strlcpy(out, dir, size);
            chosen = true;
            break;
        }
        if ((k & KEY_A) && l.count > 0) {
            char next[RS_PATH_MAX];
            rs_path_join(next, sizeof next, dir, l.names[sel]);
            rs_strlcpy(dir, next, sizeof dir);
            free_listing(&l);
            list_folder(dir, &l);
            sel = scroll = 0;
            redraw = true;
        }
        if ((k & KEY_B) && strcmp(dir, "sdmc:/") != 0) {
            char parent[RS_PATH_MAX];
            rs_dirname(dir, parent, sizeof parent);
            rs_strlcpy(dir, parent, sizeof dir);
            free_listing(&l);
            list_folder(dir, &l);
            sel = scroll = 0;
            redraw = true;
        }
        if (sel < scroll)
            scroll = sel;
        if (sel >= scroll + LIST_ROWS)
            scroll = sel - LIST_ROWS + 1;
    }
    free_listing(&l);
    return chosen;
}
