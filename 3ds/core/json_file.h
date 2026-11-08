/*
 * json_file.h - JSON documents on the SD card (config, state, queue),
 * written atomically.
 */
#ifndef RS_JSON_FILE_H
#define RS_JSON_FILE_H

#include "../vendor/cjson/cJSON.h"
#include "rs.h"

/* Reads a document. *out is NULL when the file does not exist. A corrupted
 * file is renamed "<path>.corrupt" and *out is NULL, with an explanation in
 * warning (may be NULL). The caller frees *out with cJSON_Delete. */
rs_status rs_json_read(const char *path, cJSON **out, char *warning, size_t warning_size, rs_error *err);
/* Writes a document atomically, indented. */
rs_status rs_json_write(const char *path, const cJSON *doc, rs_error *err);

/* Small accessors returning a default when the key is absent. */
const char *rs_json_str(const cJSON *obj, const char *key, const char *def);
double rs_json_num(const cJSON *obj, const char *key, double def);
bool rs_json_bool(const cJSON *obj, const char *key, bool def);

#endif
