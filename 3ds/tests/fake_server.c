/* fake_server.c - in-memory RomSync server for the tests (see fake_server.h). */
#include "fake_server.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../core/sha.h"
#include "../core/size_rule.h"

void fake_init(fake_server *s)
{
    memset(s, 0, sizeof *s);
    s->online = true;
    s->api_level = 2;
}

void fake_free(fake_server *s)
{
    for (int i = 0; i < s->version_count; i++)
        rs_buf_free(&s->versions[i].data);
}

static void set_active(fake_server *s, const char *code, int64_t id)
{
    for (int i = 0; i < s->active_count; i++)
        if (strcmp(s->active[i].code, code) == 0) {
            s->active[i].id = id;
            return;
        }
    rs_strlcpy(s->active[s->active_count].code, code, RS_GAME_ID_MAX);
    s->active[s->active_count++].id = id;
}

static size_t *chip_of(fake_server *s, const char *code)
{
    for (int i = 0; i < s->chip_count; i++)
        if (strcmp(s->chips[i].code, code) == 0)
            return &s->chips[i].size;
    return NULL;
}

static void set_chip(fake_server *s, const char *code, size_t size)
{
    size_t *c = chip_of(s, code);
    if (c) {
        *c = size;
        return;
    }
    rs_strlcpy(s->chips[s->chip_count].code, code, RS_GAME_ID_MAX);
    s->chips[s->chip_count++].size = size;
}

static fake_version *by_id(fake_server *s, int64_t id)
{
    for (int i = 0; i < s->version_count; i++)
        if (s->versions[i].id == id)
            return &s->versions[i];
    return NULL;
}

const fake_version *fake_active(const fake_server *s, const char *code)
{
    for (int i = 0; i < s->active_count; i++)
        if (strcmp(s->active[i].code, code) == 0)
            return by_id((fake_server *)s, s->active[i].id);
    return NULL;
}

static fake_version *add(fake_server *s, const char *code, const uint8_t *data, size_t len, rs_time saved_at,
                         int64_t base, bool conflict)
{
    fake_version *v = &s->versions[s->version_count++];
    memset(v, 0, sizeof *v);
    v->id = ++s->seq;
    rs_strlcpy(v->code, code, sizeof v->code);
    rs_buf_append(&v->data, data, len);
    rs_sha256_hex(data, len, v->sha);
    v->saved_at = saved_at;
    v->base = base;
    v->conflict = conflict;
    return v;
}

const fake_version *fake_add_version(fake_server *s, const char *code, const uint8_t *data, size_t len,
                                     rs_time saved_at)
{
    fake_version *v = add(s, code, data, len, saved_at, 0, false);
    set_active(s, code, v->id);
    if (!chip_of(s, code))
        set_chip(s, code, len);
    return v;
}

/* ---- HTTP -------------------------------------------------------------- */

static const char *header(const rs_http_request *req, const char *name)
{
    for (int i = 0; i < req->header_count; i++)
        if (strcmp(req->headers[i].name, name) == 0)
            return req->headers[i].value;
    return NULL;
}

static void url_decode(const char *in, char *out, size_t size)
{
    size_t k = 0;
    for (; *in && k + 1 < size; in++) {
        if (*in == '%' && in[1] && in[2]) {
            char hex[3] = {in[1], in[2], 0};
            out[k++] = (char)strtol(hex, NULL, 16);
            in += 2;
        } else {
            out[k++] = *in;
        }
    }
    out[k] = 0;
}

static void reply(rs_http_response *res, int status, const char *json)
{
    res->status = status;
    rs_buf_append(&res->body, json, strlen(json));
}

static void reply_error(rs_http_response *res, int status, const char *code)
{
    char json[128];
    snprintf(json, sizeof json, "{\"error\":{\"code\":\"%s\",\"message\":\"%s\"}}", code, code);
    reply(res, status, json);
}

static void version_json(const fake_server *s, const fake_version *v, char *out, size_t size)
{
    char saved[32], base[24] = "null";
    rs_time_format_iso(v->saved_at, saved, sizeof saved);
    if (v->base)
        snprintf(base, sizeof base, "%lld", (long long)v->base);
    const fake_version *a = fake_active(s, v->code);
    snprintf(out, size,
             "{\"id\":%lld,\"game_code\":\"%s\",\"sha256\":\"%s\",\"size\":%zu,\"saved_at\":\"%s\","
             "\"device_name\":\"dev\",\"base_version_id\":%s,\"is_active\":%s,\"conflict\":%s}",
             (long long)v->id, v->code, v->sha, v->data.len, saved, base, a == v ? "true" : "false",
             v->conflict ? "true" : "false");
}

static void upload(fake_server *s, const char *code, const rs_http_request *req, rs_http_response *res)
{
    const char *upload_id = header(req, "X-Upload-Id");
    char vj[512], json[700];
    for (int i = 0; i < s->upload_id_count; i++)
        if (strcmp(s->upload_ids[i].upload_id, upload_id) == 0) {
            /* A retry: the original answer again. */
            fake_version *v = by_id(s, s->upload_ids[i].id);
            version_json(s, v, vj, sizeof vj);
            snprintf(json, sizeof json, "{\"version\":%s,\"created\":true,\"active\":%s,\"conflict\":%s}", vj,
                     fake_active(s, code) == v ? "true" : "false", v->conflict ? "true" : "false");
            reply(res, 201, json);
            return;
        }
    if (s->refuse_uploads[0]) {
        reply_error(res, 409, s->refuse_uploads);
        return;
    }
    char sha[65];
    rs_sha256_hex(req->body, req->body_len, sha);
    if (strcmp(sha, header(req, "X-Content-SHA256")) != 0) {
        reply_error(res, 400, "hash_mismatch");
        return;
    }
    const fake_version *cur = fake_active(s, code);
    /* Size rules: padding cut down to the chip size, chip size shrunk when
     * the active version's excess is only padding. */
    size_t len = req->body_len, *chip = chip_of(s, code);
    if (chip && len != *chip) {
        if (len > *chip && rs_is_padding(req->body + *chip, len - *chip)) {
            len = *chip;
            rs_sha256_hex(req->body, len, sha);
        } else if (len < *chip && cur && cur->data.len > len &&
                   rs_is_padding(cur->data.data + len, cur->data.len - len)) {
            *chip = len;
        } else {
            reply_error(res, 409, "size_mismatch");
            return;
        }
    }
    if (!chip)
        set_chip(s, code, len);
    if (cur && strcmp(cur->sha, sha) == 0) {
        version_json(s, cur, vj, sizeof vj);
        snprintf(json, sizeof json, "{\"version\":%s,\"created\":false,\"active\":true,\"conflict\":false}", vj);
        reply(res, 200, json);
        return;
    }
    const char *base_header = header(req, "X-Base-Version");
    int64_t base = base_header && *base_header ? atoll(base_header) : 0;
    rs_time saved_at = 0;
    rs_time_parse_iso(header(req, "X-Saved-At"), &saved_at);
    bool conflict = cur && base != cur->id;
    const char *activate_header = header(req, "X-Activate");
    bool activate = !cur || (activate_header ? strcmp(activate_header, "true") == 0 : saved_at > cur->saved_at);
    fake_version *v = add(s, code, req->body, len, saved_at, base, conflict);
    rs_strlcpy(s->upload_ids[s->upload_id_count].upload_id, upload_id, 40);
    s->upload_ids[s->upload_id_count++].id = v->id;
    if (activate)
        set_active(s, code, v->id);
    version_json(s, v, vj, sizeof vj);
    snprintf(json, sizeof json, "{\"version\":%s,\"created\":true,\"active\":%s,\"conflict\":%s}", vj,
             activate ? "true" : "false", conflict ? "true" : "false");
    reply(res, 201, json);
}

static void games(fake_server *s, rs_http_response *res)
{
    rs_buf_append(&res->body, "{\"games\":[", 10);
    int written = 0;
    for (int i = 0; i < s->active_count; i++) {
        const fake_version *a = fake_active(s, s->active[i].code);
        char vj[512], g[700];
        version_json(s, a, vj, sizeof vj);
        /* "conflict" is the flag of the latest upload of the game. */
        bool conflict = false;
        for (int k = 0; k < s->version_count; k++)
            if (strcmp(s->versions[k].code, a->code) == 0)
                conflict = s->versions[k].conflict;
        snprintf(g, sizeof g, "%s{\"code\":\"%s\",\"title\":\"%s\",\"chip_size\":%zu,\"conflict\":%s,"
                 "\"active_version\":%s}",
                 written++ ? "," : "", a->code, a->code, a->data.len, conflict ? "true" : "false", vj);
        rs_buf_append(&res->body, g, strlen(g));
    }
    rs_buf_append(&res->body, "]}", 2);
    res->status = 200;
}

rs_status fake_send(void *ctx, const rs_http_request *req, rs_http_response *res, rs_error *err)
{
    fake_server *s = ctx;
    if (!s->online)
        return rs_fail(err, RS_ERR_OFFLINE, "Connexion refusée");
    if (s->server_now) {
        /* Date header of the fake clock: "Sun, 08 Nov 2026 12:00:00 GMT". */
        static const char *mon[] = {"Jan", "Feb", "Mar", "Apr", "May", "Jun",
                                    "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"};
        char iso[32];
        rs_time_format_iso(s->server_now, iso, sizeof iso);
        int y, m, d, h, mi, sec;
        sscanf(iso, "%d-%d-%dT%d:%d:%d", &y, &m, &d, &h, &mi, &sec);
        snprintf(res->date, sizeof res->date, "Sun, %02d %s %04d %02d:%02d:%02d GMT", d, mon[m - 1], y, h, mi, sec);
    }

    const char *p = strstr(req->url, "/api/v1");
    char path[256];
    url_decode(p ? p + 7 : req->url, path, sizeof path);
    char code[RS_GAME_ID_MAX + 8];
    long long id;
    size_t n = strlen(path);

    if (strcmp(req->method, "GET") == 0 && strncmp(path, "/games/", 7) == 0 && n > 14 &&
        strcmp(path + n - 7, "/active") == 0) {
        rs_strlcpy(code, path + 7, sizeof code);
        code[n - 14] = 0;
        const fake_version *v = fake_active(s, code);
        if (!v) {
            reply_error(res, 404, "not_found");
        } else {
            char vj[512], json[600];
            version_json(s, v, vj, sizeof vj);
            size_t *chip = chip_of(s, code);
            snprintf(json, sizeof json, "{\"version\":%s,\"chip_size\":%zu}", vj, chip ? *chip : 0);
            reply(res, 200, json);
        }
    } else if (strcmp(req->method, "POST") == 0 && strncmp(path, "/games/", 7) == 0 && n > 16 &&
               strcmp(path + n - 9, "/versions") == 0) {
        rs_strlcpy(code, path + 7, sizeof code);
        code[n - 16] = 0;
        s->upload_requests++;
        upload(s, code, req, res);
        if (s->drop_next_upload_response) {
            s->drop_next_upload_response = false;
            rs_buf_free(&res->body);
            return rs_fail(err, RS_ERR_OFFLINE, "Connexion coupée");
        }
    } else if (sscanf(path, "/versions/%lld/content", &id) == 1) {
        fake_version *v = by_id(s, id);
        res->status = 200;
        rs_buf_append(&res->body, v->data.data, v->data.len);
        rs_strlcpy(res->content_sha256, v->sha, sizeof res->content_sha256);
    } else if (strcmp(path, "/server") == 0) {
        if (!s->api_level) {
            reply_error(res, 404, "not_found");
        } else {
            char json[160];
            snprintf(json, sizeof json,
                     "{\"version\":\"0.5.0\",\"api_level\":%d,\"min_client_version\":\"0.4.0\",\"updates\":false}",
                     s->api_level);
            reply(res, 200, json);
        }
    } else if (strcmp(path, "/games") == 0) {
        games(s, res);
    } else if (strcmp(path, "/pair") == 0) {
        reply(res, 201, "{\"token\":\"device-token\",\"device\":{\"id\":1,\"name\":\"3DS\",\"platform\":\"3ds\"}}");
    } else {
        reply_error(res, 404, "not_found");
    }
    return RS_OK;
}
