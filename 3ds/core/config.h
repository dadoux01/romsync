/*
 * config.h - settings of the 3DS app, in sd:/3ds/romsync/config.json.
 * The device token is kept apart, in token.txt (see 3ds/README.md).
 */
#ifndef RS_CONFIG_H
#define RS_CONFIG_H

#include <stdbool.h>
#include <stddef.h>

#include "nds.h"
#include "rs.h"

#define RS_MAX_FOLDERS 8

typedef struct {
    char path[RS_PATH_MAX];
    bool recursive; /* also scan sub-folders */
} rs_rom_folder;

/* The user's answer for a ROM sharing its identifier with others. */
typedef struct {
    char rom_path[RS_PATH_MAX];
    bool share;                     /* true: same save as the others */
    char custom_id[RS_GAME_ID_MAX]; /* share == false: forced "x:" identifier */
} rs_rom_choice;

/* Last TWiLight Menu++ save slot seen for a ROM, to notice a change. */
typedef struct {
    char rom_path[RS_PATH_MAX];
    int slot;
} rs_rom_slot;

/* Identifier of a homebrew ROM (SHA-1 of the whole file), cached by path
 * and size: hashing a large file on the SD card is slow. */
typedef struct {
    char rom_path[RS_PATH_MAX];
    long long size;
    char id[RS_GAME_ID_MAX];
} rs_id_cache;

typedef struct {
    char path[RS_PATH_MAX];
    char server_url[256];
    char device_name[64];
    rs_rom_folder folders[RS_MAX_FOLDERS];
    int folder_count;
    int keep_backups;
    bool check_updates; /* look for a new version at start (true by default) */

    rs_rom_choice *choices;
    int choice_count;
    rs_rom_slot *slots;
    int slot_count;
    rs_id_cache *ids;
    int id_count;
    char warning[256];
} rs_config;

rs_status rs_config_load(rs_config *c, const char *path, rs_error *err);
rs_status rs_config_save(const rs_config *c, rs_error *err);
void rs_config_free(rs_config *c);

bool rs_config_add_folder(rs_config *c, const char *path, bool recursive);
void rs_config_remove_folder(rs_config *c, int index);

const rs_rom_choice *rs_config_choice(const rs_config *c, const char *rom_path);
/* share == true, or a valid custom_id. */
bool rs_config_set_choice(rs_config *c, const char *rom_path, bool share, const char *custom_id);

/* -1 when no slot was recorded for the ROM. */
int rs_config_slot(const rs_config *c, const char *rom_path);
bool rs_config_set_slot(rs_config *c, const char *rom_path, int slot);

const char *rs_config_cached_id(const rs_config *c, const char *rom_path, long long size);
bool rs_config_cache_id(rs_config *c, const char *rom_path, long long size, const char *id);

#endif
