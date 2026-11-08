/*
 * config.c - settings of the 3DS app (see config.h).
 */
#include "config.h"

#include <stdlib.h>
#include <string.h>

#include "json_file.h"

/* Grows a malloc'ed array by one element; returns the new element. */
static void *grow(void **items, int *count, size_t elem)
{
    void *p = realloc(*items, (size_t)(*count + 1) * elem);
    if (!p)
        return NULL;
    *items = p;
    void *e = (char *)p + (size_t)(*count) * elem;
    memset(e, 0, elem);
    (*count)++;
    return e;
}

rs_status rs_config_load(rs_config *c, const char *path, rs_error *err)
{
    memset(c, 0, sizeof *c);
    rs_strlcpy(c->path, path, sizeof c->path);
    rs_strlcpy(c->device_name, "3DS", sizeof c->device_name);
    c->keep_backups = 10;
    c->check_updates = true;
    cJSON *doc;
    rs_status st = rs_json_read(path, &doc, c->warning, sizeof c->warning, err);
    if (st != RS_OK || !doc)
        return st;

    rs_strlcpy(c->server_url, rs_json_str(doc, "server_url", ""), sizeof c->server_url);
    rs_strlcpy(c->device_name, rs_json_str(doc, "device_name", "3DS"), sizeof c->device_name);
    c->keep_backups = (int)rs_json_num(doc, "backup_count", 10);
    c->check_updates = rs_json_bool(doc, "check_updates", true);
    const cJSON *e;
    cJSON_ArrayForEach(e, cJSON_GetObjectItemCaseSensitive(doc, "rom_folders"))
        rs_config_add_folder(c, rs_json_str(e, "path", ""), rs_json_bool(e, "recursive", true));
    cJSON_ArrayForEach(e, cJSON_GetObjectItemCaseSensitive(doc, "rom_choices"))
    {
        if (e->string)
            rs_config_set_choice(c, e->string, rs_json_bool(e, "share", false), rs_json_str(e, "custom_id", ""));
    }
    cJSON_ArrayForEach(e, cJSON_GetObjectItemCaseSensitive(doc, "save_slots"))
    {
        if (e->string && cJSON_IsNumber(e))
            rs_config_set_slot(c, e->string, e->valueint);
    }
    cJSON_ArrayForEach(e, cJSON_GetObjectItemCaseSensitive(doc, "rom_ids"))
    {
        if (e->string)
            rs_config_cache_id(c, e->string, (long long)rs_json_num(e, "size", -1), rs_json_str(e, "id", ""));
    }
    cJSON_Delete(doc);
    return RS_OK;
}

rs_status rs_config_save(const rs_config *c, rs_error *err)
{
    cJSON *doc = cJSON_CreateObject();
    cJSON_AddNumberToObject(doc, "version", 1);
    cJSON_AddStringToObject(doc, "server_url", c->server_url);
    cJSON_AddStringToObject(doc, "device_name", c->device_name);
    cJSON_AddNumberToObject(doc, "backup_count", c->keep_backups);
    cJSON_AddBoolToObject(doc, "check_updates", c->check_updates);
    cJSON *folders = cJSON_AddArrayToObject(doc, "rom_folders");
    for (int i = 0; i < c->folder_count; i++) {
        cJSON *f = cJSON_CreateObject();
        cJSON_AddStringToObject(f, "path", c->folders[i].path);
        cJSON_AddBoolToObject(f, "recursive", c->folders[i].recursive);
        cJSON_AddItemToArray(folders, f);
    }
    cJSON *choices = cJSON_AddObjectToObject(doc, "rom_choices");
    for (int i = 0; i < c->choice_count; i++) {
        cJSON *ch = cJSON_AddObjectToObject(choices, c->choices[i].rom_path);
        cJSON_AddBoolToObject(ch, "share", c->choices[i].share);
        if (!c->choices[i].share)
            cJSON_AddStringToObject(ch, "custom_id", c->choices[i].custom_id);
    }
    cJSON *slots = cJSON_AddObjectToObject(doc, "save_slots");
    for (int i = 0; i < c->slot_count; i++)
        cJSON_AddNumberToObject(slots, c->slots[i].rom_path, c->slots[i].slot);
    cJSON *ids = cJSON_AddObjectToObject(doc, "rom_ids");
    for (int i = 0; i < c->id_count; i++) {
        cJSON *id = cJSON_AddObjectToObject(ids, c->ids[i].rom_path);
        cJSON_AddNumberToObject(id, "size", (double)c->ids[i].size);
        cJSON_AddStringToObject(id, "id", c->ids[i].id);
    }
    rs_status st = rs_json_write(c->path, doc, err);
    cJSON_Delete(doc);
    return st;
}

void rs_config_free(rs_config *c)
{
    free(c->choices);
    free(c->slots);
    free(c->ids);
    c->choices = NULL;
    c->slots = NULL;
    c->ids = NULL;
    c->choice_count = c->slot_count = c->id_count = 0;
}

bool rs_config_add_folder(rs_config *c, const char *path, bool recursive)
{
    if (!path[0] || c->folder_count == RS_MAX_FOLDERS)
        return false;
    for (int i = 0; i < c->folder_count; i++)
        if (strcmp(c->folders[i].path, path) == 0) {
            c->folders[i].recursive = recursive;
            return true;
        }
    rs_strlcpy(c->folders[c->folder_count].path, path, RS_PATH_MAX);
    c->folders[c->folder_count++].recursive = recursive;
    return true;
}

void rs_config_remove_folder(rs_config *c, int index)
{
    if (index < 0 || index >= c->folder_count)
        return;
    memmove(&c->folders[index], &c->folders[index + 1], (size_t)(c->folder_count - index - 1) * sizeof c->folders[0]);
    c->folder_count--;
}

const rs_rom_choice *rs_config_choice(const rs_config *c, const char *rom_path)
{
    for (int i = 0; i < c->choice_count; i++)
        if (strcmp(c->choices[i].rom_path, rom_path) == 0)
            return &c->choices[i];
    return NULL;
}

bool rs_config_set_choice(rs_config *c, const char *rom_path, bool share, const char *custom_id)
{
    if (!share && !rs_game_id_valid(custom_id))
        return false;
    rs_rom_choice *ch = (rs_rom_choice *)rs_config_choice(c, rom_path);
    if (!ch && !(ch = grow((void **)&c->choices, &c->choice_count, sizeof *ch)))
        return false;
    rs_strlcpy(ch->rom_path, rom_path, sizeof ch->rom_path);
    ch->share = share;
    rs_strlcpy(ch->custom_id, share ? "" : custom_id, sizeof ch->custom_id);
    return true;
}

int rs_config_slot(const rs_config *c, const char *rom_path)
{
    for (int i = 0; i < c->slot_count; i++)
        if (strcmp(c->slots[i].rom_path, rom_path) == 0)
            return c->slots[i].slot;
    return -1;
}

bool rs_config_set_slot(rs_config *c, const char *rom_path, int slot)
{
    for (int i = 0; i < c->slot_count; i++)
        if (strcmp(c->slots[i].rom_path, rom_path) == 0) {
            c->slots[i].slot = slot;
            return true;
        }
    rs_rom_slot *s = grow((void **)&c->slots, &c->slot_count, sizeof *s);
    if (!s)
        return false;
    rs_strlcpy(s->rom_path, rom_path, sizeof s->rom_path);
    s->slot = slot;
    return true;
}

const char *rs_config_cached_id(const rs_config *c, const char *rom_path, long long size)
{
    for (int i = 0; i < c->id_count; i++)
        if (strcmp(c->ids[i].rom_path, rom_path) == 0 && c->ids[i].size == size)
            return c->ids[i].id;
    return NULL;
}

bool rs_config_cache_id(rs_config *c, const char *rom_path, long long size, const char *id)
{
    if (!rs_game_id_valid(id))
        return false;
    rs_id_cache *e = NULL;
    for (int i = 0; i < c->id_count; i++)
        if (strcmp(c->ids[i].rom_path, rom_path) == 0)
            e = &c->ids[i];
    if (!e && !(e = grow((void **)&c->ids, &c->id_count, sizeof *e)))
        return false;
    rs_strlcpy(e->rom_path, rom_path, sizeof e->rom_path);
    e->size = size;
    rs_strlcpy(e->id, id, sizeof e->id);
    return true;
}
