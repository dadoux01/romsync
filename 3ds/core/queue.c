/*
 * queue.c - persistent upload queue (see queue.h).
 *
 * queue.json: { "version": 1, "uploads": [ { "upload_id", "game_id",
 *   "save_path", "sha256", "size", "saved_at", "created_at", "emulator",
 *   "title" }, ... ] }, the same shape as the Flutter client's.
 */
#include "queue.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "json_file.h"
#include "platform.h"

static void queue_file(const rs_queue *q, char *out, size_t size)
{
    rs_path_join(out, size, q->dir, "queue.json");
}

static void content_file(const rs_queue *q, const char *upload_id, char *out, size_t size)
{
    char name[48];
    snprintf(name, sizeof name, "%s.bin", upload_id);
    rs_path_join(out, size, q->dir, name);
}

static rs_status persist(const rs_queue *q, rs_error *err)
{
    cJSON *doc = cJSON_CreateObject();
    cJSON_AddNumberToObject(doc, "version", 1);
    cJSON *list = cJSON_AddArrayToObject(doc, "uploads");
    for (int i = 0; i < q->count; i++) {
        const rs_upload *u = &q->items[i];
        char saved[32], created[32];
        rs_time_format_iso(u->saved_at, saved, sizeof saved);
        rs_time_format_iso(u->created_at, created, sizeof created);
        cJSON *e = cJSON_CreateObject();
        cJSON_AddStringToObject(e, "upload_id", u->upload_id);
        cJSON_AddStringToObject(e, "game_id", u->game_id);
        cJSON_AddStringToObject(e, "save_path", u->save_path);
        cJSON_AddStringToObject(e, "sha256", u->sha256);
        cJSON_AddNumberToObject(e, "size", (double)u->size);
        cJSON_AddStringToObject(e, "saved_at", saved);
        cJSON_AddStringToObject(e, "created_at", created);
        cJSON_AddStringToObject(e, "emulator", u->emulator);
        if (u->title[0])
            cJSON_AddStringToObject(e, "title", u->title);
        else
            cJSON_AddNullToObject(e, "title");
        cJSON_AddItemToArray(list, e);
    }
    char path[RS_PATH_MAX];
    queue_file(q, path, sizeof path);
    rs_status st = rs_json_write(path, doc, err);
    cJSON_Delete(doc);
    return st;
}

static bool push(rs_queue *q, const rs_upload *u)
{
    rs_upload *items = realloc(q->items, (size_t)(q->count + 1) * sizeof *items);
    if (!items)
        return false;
    q->items = items;
    q->items[q->count++] = *u;
    return true;
}

rs_status rs_queue_open(rs_queue *q, const char *dir, rs_error *err)
{
    memset(q, 0, sizeof *q);
    rs_strlcpy(q->dir, dir, sizeof q->dir);
    char path[RS_PATH_MAX];
    queue_file(q, path, sizeof path);
    cJSON *doc;
    rs_status st = rs_json_read(path, &doc, q->warning, sizeof q->warning, err);
    if (st != RS_OK || !doc)
        return st;
    const cJSON *e;
    cJSON_ArrayForEach(e, cJSON_GetObjectItemCaseSensitive(doc, "uploads"))
    {
        rs_upload u = {0};
        rs_strlcpy(u.upload_id, rs_json_str(e, "upload_id", ""), sizeof u.upload_id);
        rs_strlcpy(u.game_id, rs_json_str(e, "game_id", ""), sizeof u.game_id);
        rs_strlcpy(u.save_path, rs_json_str(e, "save_path", ""), sizeof u.save_path);
        rs_strlcpy(u.sha256, rs_json_str(e, "sha256", ""), sizeof u.sha256);
        u.size = (size_t)rs_json_num(e, "size", 0);
        rs_time_parse_iso(rs_json_str(e, "saved_at", ""), &u.saved_at);
        rs_time_parse_iso(rs_json_str(e, "created_at", ""), &u.created_at);
        rs_strlcpy(u.emulator, rs_json_str(e, "emulator", ""), sizeof u.emulator);
        rs_strlcpy(u.title, rs_json_str(e, "title", ""), sizeof u.title);
        /* Drop entries whose content file is missing: they cannot be sent. */
        char content[RS_PATH_MAX];
        content_file(q, u.upload_id, content, sizeof content);
        if (!u.upload_id[0] || !rs_file_exists(content))
            continue;
        if (!push(q, &u)) {
            st = rs_fail(err, RS_ERR_NOMEM, "Mémoire insuffisante");
            break;
        }
    }
    cJSON_Delete(doc);
    return st;
}

void rs_queue_close(rs_queue *q)
{
    free(q->items);
    q->items = NULL;
    q->count = 0;
}

rs_status rs_queue_add(rs_queue *q, const char *game_id, const char *save_path, const uint8_t *data,
                       size_t len, const char *sha256, rs_time saved_at, const char *emulator,
                       const char *title, rs_time now, rs_upload *added, rs_error *err)
{
    rs_upload u = {0};
    rs_uuid4(u.upload_id);
    rs_strlcpy(u.game_id, game_id, sizeof u.game_id);
    rs_strlcpy(u.save_path, save_path, sizeof u.save_path);
    rs_strlcpy(u.sha256, sha256, sizeof u.sha256);
    u.size = len;
    u.saved_at = saved_at;
    u.created_at = now;
    rs_strlcpy(u.emulator, emulator ? emulator : "", sizeof u.emulator);
    rs_strlcpy(u.title, title ? title : "", sizeof u.title);

    /* The content first: an entry in queue.json always has its content. */
    char content[RS_PATH_MAX];
    content_file(q, u.upload_id, content, sizeof content);
    rs_status st = rs_write_file_atomic(content, data, len, err);
    if (st != RS_OK)
        return st;
    if (!push(q, &u))
        return rs_fail(err, RS_ERR_NOMEM, "Mémoire insuffisante");
    if (added)
        *added = u;
    return persist(q, err);
}

rs_status rs_queue_content(const rs_queue *q, const rs_upload *u, rs_buf *out, rs_error *err)
{
    char content[RS_PATH_MAX];
    content_file(q, u->upload_id, content, sizeof content);
    return rs_read_file(content, out, err);
}

rs_status rs_queue_remove(rs_queue *q, const char *upload_id, rs_error *err)
{
    for (int i = 0; i < q->count; i++) {
        if (strcmp(q->items[i].upload_id, upload_id) != 0)
            continue;
        /* Keep the order: the queue is first in, first out. */
        memmove(&q->items[i], &q->items[i + 1], (size_t)(q->count - i - 1) * sizeof q->items[0]);
        q->count--;
        rs_status st = persist(q, err);
        char content[RS_PATH_MAX];
        content_file(q, upload_id, content, sizeof content);
        remove(content);
        return st;
    }
    return RS_OK;
}

int rs_queue_count_for(const rs_queue *q, const char *save_path)
{
    int n = 0;
    for (int i = 0; i < q->count; i++)
        n += strcmp(q->items[i].save_path, save_path) == 0;
    return n;
}

bool rs_queue_has(const rs_queue *q, const char *save_path, const char *game_id, const char *sha256)
{
    for (int i = 0; i < q->count; i++) {
        const rs_upload *u = &q->items[i];
        if (strcmp(u->save_path, save_path) == 0 && strcmp(u->game_id, game_id) == 0 &&
            strcmp(u->sha256, sha256) == 0)
            return true;
    }
    return false;
}

void rs_uuid4(char out[37])
{
    uint8_t b[16];
    rs_platform_random(b, sizeof b);
    b[6] = (uint8_t)((b[6] & 0x0F) | 0x40); /* version 4 */
    b[8] = (uint8_t)((b[8] & 0x3F) | 0x80); /* RFC 4122 variant */
    char hex[33];
    rs_hex(b, sizeof b, hex);
    snprintf(out, 37, "%.8s-%.4s-%.4s-%.4s-%.12s", hex, hex + 8, hex + 12, hex + 16, hex + 20);
}
