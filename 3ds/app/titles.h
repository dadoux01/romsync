/*
 * titles.h - the 3DS games of the console and their save archives
 * (docs/SPEC.md, "Jeux 3DS"), read and written as Checkpoint does: games
 * installed on the SD card and the inserted cartridge, each save being the
 * "user save data" archive of the system, synced as a save made of a folder
 * through an rs_save_io.
 */
#ifndef RS_TITLES_H
#define RS_TITLES_H

#include <3ds.h>
#include <stdbool.h>

#include "../core/library.h"

typedef struct {
    u64 id;
    FS_MediaType media;
    char name[64];  /* English short title of the icon, else the product code */
    bool has_save;  /* the save archive opens: the game created its save */
    rs_save_io io;  /* ctx = this title */
} ctr_title;

typedef struct {
    ctr_title *items;
    int count;
    /* Why the list could not be read ("am" service), or "". */
    char error[160];
} ctr_titles;

/* Lists the games (title IDs 00040000xxxxxxxx) of the SD card and of the
 * cartridge; a cartridge whose game is also installed is left out. */
void titles_list(ctr_titles *out);
void titles_free(ctr_titles *t);

/* Adds one library entry per game of t to lib (after its DS games), with
 * the "tree" profile; the entries point into t, which must outlive lib's
 * use of them. backup_root is the folder of the .tar copies. */
void titles_add_to_library(ctr_titles *t, const rs_profile *tree, const char *backup_root, rs_library *lib);

/* The title of a library entry added by titles_add_to_library, or NULL. */
ctr_title *titles_of_entry(const rs_entry *entry);

/* Starts the game once RomSync exits (application jump). */
bool titles_launch(const ctr_title *t, char *why, size_t size);

#endif
