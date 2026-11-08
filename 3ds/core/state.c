/*
 * state.c - sync state of each save file (see state.h).
 *
 * state.json:
 *   { "version": 1,
 *     "clock": { "known": true, "offset": -3600 },
 *     "saves": { "<save path>": { "game_id", "last_synced_version_id",
 *                                 "last_synced_hash", "last_synced_at" } } }
 * The "saves" object has the same shape as the Flutter client's.
 */
#include "state.h"

#include <stdlib.h>
#include <string.h>

#include "json_file.h"

static rs_status put(rs_state_store *s, const char *save_path, const char *game_id, int64_t version_id,
                     const char *hash, rs_time at, rs_error *err);

rs_status rs_state_open(rs_state_store *s, const char *path, rs_error *err)
{
    memset(s, 0, sizeof *s);
    rs_strlcpy(s->path, path, sizeof s->path);
    cJSON *doc;
    rs_status st = rs_json_read(path, &doc, s->warning, sizeof s->warning, err);
    if (st != RS_OK || !doc)
        return st;

    const cJSON *clock = cJSON_GetObjectItemCaseSensitive(doc, "clock");
    s->clock.known = rs_json_bool(clock, "known", false);
    s->clock.offset = (int64_t)rs_json_num(clock, "offset", 0);

    const cJSON *saves = cJSON_GetObjectItemCaseSensitive(doc, "saves");
    const cJSON *e;
    cJSON_ArrayForEach(e, saves)
    {
        const char *game = rs_json_str(e, "game_id", NULL);
        if (!e->string || !game)
            continue;
        rs_time at = 0;
        rs_time_parse_iso(rs_json_str(e, "last_synced_at", ""), &at);
        st = put(s, e->string, game, (int64_t)rs_json_num(e, "last_synced_version_id", 0),
                 rs_json_str(e, "last_synced_hash", ""), at, err);
        if (st != RS_OK)
            break;
    }
    cJSON_Delete(doc);
    return st;
}

void rs_state_close(rs_state_store *s)
{
    free(s->items);
    s->items = NULL;
    s->count = 0;
}

static rs_save_state *find(const rs_state_store *s, const char *save_path)
{
    for (int i = 0; i < s->count; i++)
        if (strcmp(s->items[i].save_path, save_path) == 0)
            return &s->items[i];
    return NULL;
}

const rs_save_state *rs_state_get(const rs_state_store *s, const char *save_path)
{
    return find(s, save_path);
}

const rs_save_state *rs_state_for(const rs_state_store *s, const char *save_path, const char *game_id)
{
    const rs_save_state *st = find(s, save_path);
    return st && strcmp(st->game_id, game_id) == 0 ? st : NULL;
}

/* Adds or replaces a state in memory (without saving the file). */
static rs_status put(rs_state_store *s, const char *save_path, const char *game_id, int64_t version_id,
                     const char *hash, rs_time at, rs_error *err)
{
    rs_save_state *st = find(s, save_path);
    if (!st) {
        rs_save_state *items = realloc(s->items, (size_t)(s->count + 1) * sizeof *items);
        if (!items)
            return rs_fail(err, RS_ERR_NOMEM, "Mémoire insuffisante");
        s->items = items;
        st = &s->items[s->count++];
        memset(st, 0, sizeof *st);
        rs_strlcpy(st->save_path, save_path, sizeof st->save_path);
    }
    rs_strlcpy(st->game_id, game_id, sizeof st->game_id);
    st->version_id = version_id;
    rs_strlcpy(st->hash, hash, sizeof st->hash);
    st->synced_at = at;
    return RS_OK;
}

rs_status rs_state_record(rs_state_store *s, const char *save_path, const char *game_id, int64_t version_id,
                          const char *hash, rs_time at, rs_error *err)
{
    rs_status st = put(s, save_path, game_id, version_id, hash, at, err);
    return st == RS_OK ? rs_state_save(s, err) : st;
}

rs_status rs_state_forget(rs_state_store *s, const char *save_path, rs_error *err)
{
    rs_save_state *st = find(s, save_path);
    if (!st)
        return RS_OK;
    *st = s->items[--s->count];
    return rs_state_save(s, err);
}

rs_status rs_state_save(rs_state_store *s, rs_error *err)
{
    cJSON *doc = cJSON_CreateObject();
    cJSON_AddNumberToObject(doc, "version", 1);
    cJSON *clock = cJSON_AddObjectToObject(doc, "clock");
    cJSON_AddBoolToObject(clock, "known", s->clock.known);
    cJSON_AddNumberToObject(clock, "offset", (double)s->clock.offset);
    cJSON *saves = cJSON_AddObjectToObject(doc, "saves");
    for (int i = 0; i < s->count; i++) {
        const rs_save_state *st = &s->items[i];
        cJSON *e = cJSON_AddObjectToObject(saves, st->save_path);
        cJSON_AddStringToObject(e, "game_id", st->game_id);
        if (st->version_id)
            cJSON_AddNumberToObject(e, "last_synced_version_id", (double)st->version_id);
        else
            cJSON_AddNullToObject(e, "last_synced_version_id");
        cJSON_AddStringToObject(e, "last_synced_hash", st->hash);
        char at[32];
        rs_time_format_iso(st->synced_at, at, sizeof at);
        cJSON_AddStringToObject(e, "last_synced_at", at);
    }
    rs_status st = rs_json_write(s->path, doc, err);
    cJSON_Delete(doc);
    return st;
}
