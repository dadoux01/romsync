/*
 * api.c - RomSync REST API client (see api.h).
 *
 * Every function follows the same pattern: build an rs_http_request, send
 * it with api->send, turn an HTTP error into RS_ERR_API (with the server's
 * {"error": {"code", "message"}}), then read the JSON answer with cJSON.
 */
#include "api.h"

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../vendor/cjson/cJSON.h"
#include "json_file.h"
#include "sha.h"

/* ---- Helpers ----------------------------------------------------------- */

bool rs_api_normalize_url(const char *in, char *out, size_t size)
{
    while (isspace((unsigned char)*in))
        in++;
    char tmp[256];
    if (strstr(in, "://"))
        rs_strlcpy(tmp, in, sizeof tmp);
    else
        snprintf(tmp, sizeof tmp, "http://%s", in);
    size_t n = strlen(tmp);
    while (n > 0 && (tmp[n - 1] == '/' || isspace((unsigned char)tmp[n - 1])))
        tmp[--n] = 0;
    const char *host;
    if (strncmp(tmp, "http://", 7) == 0)
        host = tmp + 7;
    else if (strncmp(tmp, "https://", 8) == 0)
        host = tmp + 8;
    else
        return false;
    if (*host == 0 || *host == ':' || *host == '/' || strchr(host, ' '))
        return false;
    if (strlen(tmp) + 1 > size)
        return false;
    rs_strlcpy(out, tmp, size);
    return true;
}

void rs_url_encode(const char *s, char *out, size_t size)
{
    static const char hex[] = "0123456789ABCDEF";
    size_t k = 0;
    for (const unsigned char *p = (const unsigned char *)s; *p && k + 4 < size; p++) {
        if (isalnum(*p) || strchr("-_.!~*'()", *p)) {
            out[k++] = (char)*p;
        } else {
            out[k++] = '%';
            out[k++] = hex[*p >> 4];
            out[k++] = hex[*p & 15];
        }
    }
    out[k] = 0;
}

static void api_url(const rs_api *api, const char *path, char *out, size_t size)
{
    snprintf(out, size, "%s/api/v1%s", api->base_url, path);
}

/* Sends req with the device token, records the server clock, and turns an
 * HTTP error into RS_ERR_API. res must be freed by the caller. */
static rs_status api_send(rs_api *api, rs_http_request *req, rs_http_response *res, rs_error *err)
{
    char auth[160];
    if (api->token[0]) {
        snprintf(auth, sizeof auth, "Bearer %s", api->token);
        rs_http_add_header(req, "Authorization", auth);
    }
    memset(res, 0, sizeof *res);
    rs_status st = api->send(api->send_ctx, req, res, err);
    if (st != RS_OK)
        return st;

    /* The server's "Date" header gives its clock: remember the gap with the
     * console clock to correct the dates of the next uploads. */
    rs_time server_time;
    if (api->clock && api->now && rs_time_parse_http(res->date, &server_time))
        rs_clock_observe(api->clock, server_time, api->now(api->now_ctx));

    if (res->status < 400)
        return RS_OK;
    char code[32] = "internal", message[200];
    snprintf(message, sizeof message, "HTTP %d", res->status);
    if (rs_buf_terminate(&res->body)) {
        cJSON *j = cJSON_Parse((const char *)res->body.data);
        const cJSON *e = cJSON_GetObjectItemCaseSensitive(j, "error");
        rs_strlcpy(code, rs_json_str(e, "code", code), sizeof code);
        rs_strlcpy(message, rs_json_str(e, "message", message), sizeof message);
        cJSON_Delete(j);
    }
    rs_fail(err, RS_ERR_API, "%s", message);
    if (err) {
        err->http_status = res->status;
        rs_strlcpy(err->code, code, sizeof err->code);
    }
    return RS_ERR_API;
}

/* Parses the JSON body of a successful response. */
static rs_status json_body(rs_http_response *res, cJSON **out, rs_error *err)
{
    if (!rs_buf_terminate(&res->body))
        return rs_fail(err, RS_ERR_NOMEM, "Mémoire insuffisante");
    *out = cJSON_Parse((const char *)res->body.data);
    if (!*out)
        return rs_fail(err, RS_ERR_FORMAT, "Réponse illisible du serveur");
    return RS_OK;
}

static void parse_version(const cJSON *j, rs_version *v)
{
    memset(v, 0, sizeof *v);
    v->id = (int64_t)rs_json_num(j, "id", 0);
    rs_strlcpy(v->game_code, rs_json_str(j, "game_code", ""), sizeof v->game_code);
    rs_strlcpy(v->sha256, rs_json_str(j, "sha256", ""), sizeof v->sha256);
    v->size = (size_t)rs_json_num(j, "size", 0);
    rs_time_parse_iso(rs_json_str(j, "saved_at", ""), &v->saved_at);
    rs_strlcpy(v->device_name, rs_json_str(j, "device_name", ""), sizeof v->device_name);
    v->conflict = rs_json_bool(j, "conflict", false);
}

/* ---- Routes ------------------------------------------------------------ */

rs_status rs_api_pair(rs_api *api, const char *code, const char *name, const char *platform, char *token,
                      size_t token_size, rs_error *err)
{
    cJSON *body = cJSON_CreateObject();
    cJSON_AddStringToObject(body, "code", code);
    cJSON_AddStringToObject(body, "name", name);
    cJSON_AddStringToObject(body, "platform", platform);
    char *text = cJSON_PrintUnformatted(body);
    cJSON_Delete(body);

    char url[512];
    api_url(api, "/pair", url, sizeof url);
    rs_http_request req = {.method = "POST", .url = url, .body = (const uint8_t *)text, .body_len = strlen(text)};
    rs_http_add_header(&req, "Content-Type", "application/json");
    rs_http_response res;
    rs_status st = api_send(api, &req, &res, err);
    free(text);
    cJSON *j = NULL;
    if (st == RS_OK)
        st = json_body(&res, &j, err);
    if (st == RS_OK) {
        const char *t = rs_json_str(j, "token", NULL);
        if (!t || strlen(t) + 1 > token_size)
            st = rs_fail(err, RS_ERR_FORMAT, "Jeton absent de la réponse");
        else
            rs_strlcpy(token, t, token_size);
    }
    cJSON_Delete(j);
    rs_http_response_free(&res);
    return st;
}

rs_status rs_api_active(rs_api *api, const char *game_id, rs_version *out, bool *exists, int64_t *chip_size,
                        rs_error *err)
{
    if (chip_size)
        *chip_size = 0;
    char id[RS_GAME_ID_MAX * 3], path[200], url[512];
    rs_url_encode(game_id, id, sizeof id);
    snprintf(path, sizeof path, "/games/%s/active", id);
    api_url(api, path, url, sizeof url);
    rs_http_request req = {.method = "GET", .url = url};
    rs_http_response res;
    rs_error local = {0};
    rs_status st = api_send(api, &req, &res, &local);
    *exists = false;
    if (st == RS_ERR_API && local.http_status == 404) {
        /* No active version yet: not an error. */
        rs_http_response_free(&res);
        return RS_OK;
    }
    if (err && st != RS_OK)
        *err = local;
    cJSON *j = NULL;
    if (st == RS_OK)
        st = json_body(&res, &j, err);
    if (st == RS_OK) {
        parse_version(cJSON_GetObjectItemCaseSensitive(j, "version"), out);
        *exists = true;
        if (chip_size)
            *chip_size = (int64_t)rs_json_num(j, "chip_size", 0);
    }
    cJSON_Delete(j);
    rs_http_response_free(&res);
    return st;
}

rs_status rs_api_upload(rs_api *api, const char *game_id, const uint8_t *data, size_t len, rs_time saved_at,
                        const char *upload_id, int64_t base_version, const char *emulator, const char *title,
                        rs_activation activate, rs_upload_result *out, rs_error *err)
{
    char id[RS_GAME_ID_MAX * 3], path[200], url[512];
    rs_url_encode(game_id, id, sizeof id);
    snprintf(path, sizeof path, "/games/%s/versions", id);
    api_url(api, path, url, sizeof url);

    char saved[32], base[24] = "", sha[65], encoded_title[200];
    rs_time_format_iso(saved_at, saved, sizeof saved);
    if (base_version)
        snprintf(base, sizeof base, "%lld", (long long)base_version);
    rs_sha256_hex(data, len, sha);

    rs_http_request req = {.method = "POST", .url = url, .body = data, .body_len = len};
    rs_http_add_header(&req, "Content-Type", "application/octet-stream");
    rs_http_add_header(&req, "X-Upload-Id", upload_id);
    rs_http_add_header(&req, "X-Saved-At", saved);
    rs_http_add_header(&req, "X-Base-Version", base);
    rs_http_add_header(&req, "X-Emulator", emulator ? emulator : "");
    rs_http_add_header(&req, "X-Content-SHA256", sha);
    if (title && title[0]) {
        /* Percent-encoded: HTTP headers only carry Latin-1. */
        rs_url_encode(title, encoded_title, sizeof encoded_title);
        rs_http_add_header(&req, "X-Game-Title", encoded_title);
    }
    /* The user's choice after a divergence; absent: most recent wins. */
    if (activate != RS_ACTIVATE_AUTO)
        rs_http_add_header(&req, "X-Activate", activate == RS_ACTIVATE_ALWAYS ? "true" : "false");
    rs_http_response res;
    rs_status st = api_send(api, &req, &res, err);
    cJSON *j = NULL;
    if (st == RS_OK)
        st = json_body(&res, &j, err);
    if (st == RS_OK) {
        parse_version(cJSON_GetObjectItemCaseSensitive(j, "version"), &out->version);
        out->created = rs_json_bool(j, "created", false);
        out->active = rs_json_bool(j, "active", false);
        out->conflict = rs_json_bool(j, "conflict", false);
    }
    cJSON_Delete(j);
    rs_http_response_free(&res);
    return st;
}

rs_status rs_api_download(rs_api *api, int64_t version_id, rs_buf *out, rs_error *err)
{
    char path[64], url[512];
    snprintf(path, sizeof path, "/versions/%lld/content", (long long)version_id);
    api_url(api, path, url, sizeof url);
    rs_http_request req = {.method = "GET", .url = url};
    rs_http_response res;
    rs_status st = api_send(api, &req, &res, err);
    if (st == RS_OK && res.content_sha256[0]) {
        char sha[65];
        rs_sha256_hex(res.body.data, res.body.len, sha);
        if (strcmp(sha, res.content_sha256) != 0)
            st = rs_fail(err, RS_ERR_FORMAT, "Save téléchargée corrompue (hash différent)");
    }
    if (st == RS_OK) {
        /* Hand the body over instead of copying it. */
        rs_buf_free(out);
        *out = res.body;
        res.body = (rs_buf){0};
    }
    rs_http_response_free(&res);
    return st;
}

rs_status rs_api_games(rs_api *api, rs_remote_game **games, int *count, rs_error *err)
{
    *games = NULL;
    *count = 0;
    char url[512];
    api_url(api, "/games", url, sizeof url);
    rs_http_request req = {.method = "GET", .url = url};
    rs_http_response res;
    rs_status st = api_send(api, &req, &res, err);
    cJSON *j = NULL;
    if (st == RS_OK)
        st = json_body(&res, &j, err);
    if (st == RS_OK) {
        const cJSON *list = cJSON_GetObjectItemCaseSensitive(j, "games");
        int n = cJSON_GetArraySize(list);
        *games = calloc(n > 0 ? (size_t)n : 1, sizeof **games);
        if (!*games) {
            st = rs_fail(err, RS_ERR_NOMEM, "Mémoire insuffisante");
        } else {
            const cJSON *g;
            cJSON_ArrayForEach(g, list)
            {
                rs_remote_game *r = &(*games)[(*count)++];
                rs_strlcpy(r->code, rs_json_str(g, "code", ""), sizeof r->code);
                rs_strlcpy(r->title, rs_json_str(g, "title", ""), sizeof r->title);
                r->conflict = rs_json_bool(g, "conflict", false);
                r->chip_size = (int64_t)rs_json_num(g, "chip_size", 0);
                const cJSON *a = cJSON_GetObjectItemCaseSensitive(g, "active_version");
                r->has_active = cJSON_IsObject(a);
                if (r->has_active)
                    parse_version(a, &r->active);
            }
        }
    }
    cJSON_Delete(j);
    rs_http_response_free(&res);
    return st;
}

/* ---- http.h helpers ---------------------------------------------------- */

void rs_http_add_header(rs_http_request *req, const char *name, const char *value)
{
    if (req->header_count < RS_HTTP_MAX_HEADERS)
        req->headers[req->header_count++] = (rs_http_header){name, value};
}

void rs_http_response_free(rs_http_response *res)
{
    rs_buf_free(&res->body);
}
