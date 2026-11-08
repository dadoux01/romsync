/*
 * json_file.c - JSON documents on disk (see json_file.h).
 */
#include "json_file.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

rs_status rs_json_read(const char *path, cJSON **out, char *warning, size_t warning_size, rs_error *err)
{
    *out = NULL;
    if (warning && warning_size)
        warning[0] = 0;
    rs_buf b = {0};
    rs_status st = rs_read_file(path, &b, err);
    if (st == RS_ERR_NOT_FOUND)
        return RS_OK;
    if (st != RS_OK)
        return st;
    if (!rs_buf_terminate(&b)) {
        rs_buf_free(&b);
        return rs_fail(err, RS_ERR_NOMEM, "Mémoire insuffisante");
    }
    *out = cJSON_Parse((const char *)b.data);
    rs_buf_free(&b);
    if (!*out) {
        /* Keep the broken file for inspection and start again empty, rather
         * than refusing to start. */
        char aside[RS_PATH_MAX];
        snprintf(aside, sizeof aside, "%s.corrupt", path);
        remove(aside);
        rename(path, aside);
        if (warning)
            snprintf(warning, warning_size, "Fichier illisible mis de côté : %s", aside);
    }
    return RS_OK;
}

rs_status rs_json_write(const char *path, const cJSON *doc, rs_error *err)
{
    char *text = cJSON_Print(doc);
    if (!text)
        return rs_fail(err, RS_ERR_NOMEM, "Mémoire insuffisante");
    rs_status st = rs_write_file_atomic(path, text, strlen(text), err);
    free(text);
    return st;
}

const char *rs_json_str(const cJSON *obj, const char *key, const char *def)
{
    const cJSON *v = cJSON_GetObjectItemCaseSensitive(obj, key);
    return cJSON_IsString(v) ? v->valuestring : def;
}

double rs_json_num(const cJSON *obj, const char *key, double def)
{
    const cJSON *v = cJSON_GetObjectItemCaseSensitive(obj, key);
    return cJSON_IsNumber(v) ? v->valuedouble : def;
}

bool rs_json_bool(const cJSON *obj, const char *key, bool def)
{
    const cJSON *v = cJSON_GetObjectItemCaseSensitive(obj, key);
    return cJSON_IsBool(v) ? cJSON_IsTrue(v) : def;
}
