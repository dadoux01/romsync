/*
 * profile.c - conversion profiles (see profile.h).
 */
#include "profile.h"

#include <dirent.h>
#include <stdlib.h>
#include <string.h>

#include "../vendor/cjson/cJSON.h"

/* ---- Parsing ----------------------------------------------------------- */

static bool copy_string(const cJSON *obj, const char *key, char *out, size_t size)
{
    const cJSON *v = cJSON_GetObjectItemCaseSensitive(obj, key);
    if (!cJSON_IsString(v))
        return false;
    rs_strlcpy(out, v->valuestring, size);
    return true;
}

static rs_status parse_field(const char *profile, const cJSON *j, rs_profile_field *f, rs_error *err)
{
    if (!copy_string(j, "name", f->name, sizeof f->name))
        return rs_fail(err, RS_ERR_FORMAT, "profil %s : champ sans nom", profile);
    const cJSON *type = cJSON_GetObjectItemCaseSensitive(j, "type");
    if (!cJSON_IsString(type) || strcmp(type->valuestring, "u32le") != 0)
        return rs_fail(err, RS_ERR_FORMAT, "profil %s : type de champ non géré", profile);
    const cJSON *v = cJSON_GetObjectItemCaseSensitive(j, "value");
    if (cJSON_IsNumber(v)) {
        f->kind = RS_FIELD_NUMBER;
        f->number = (uint32_t)v->valuedouble;
    } else if (cJSON_IsString(v) && strcmp(v->valuestring, "raw_size") == 0) {
        f->kind = RS_FIELD_RAW_SIZE;
    } else if (cJSON_IsString(v) && strcmp(v->valuestring, "desmume_save_type") == 0) {
        f->kind = RS_FIELD_DESMUME_SAVE_TYPE;
    } else if (cJSON_IsString(v) && strcmp(v->valuestring, "desmume_addr_size") == 0) {
        f->kind = RS_FIELD_DESMUME_ADDR_SIZE;
    } else {
        return rs_fail(err, RS_ERR_FORMAT, "profil %s : valeur calculée inconnue", profile);
    }
    return RS_OK;
}

rs_status rs_profile_parse(const char *json, rs_profile *p, rs_error *err)
{
    memset(p, 0, sizeof *p);
    cJSON *j = cJSON_Parse(json);
    if (!j)
        return rs_fail(err, RS_ERR_FORMAT, "profil : JSON invalide");
    rs_status st = RS_OK;
    if (!copy_string(j, "id", p->id, sizeof p->id) || !copy_string(j, "name", p->name, sizeof p->name) ||
        !copy_string(j, "status", p->status, sizeof p->status) ||
        !copy_string(j, "extension", p->extension, sizeof p->extension)) {
        st = rs_fail(err, RS_ERR_FORMAT, "profil : champ obligatoire manquant");
        goto done;
    }
    const cJSON *header = cJSON_GetObjectItemCaseSensitive(j, "header");
    if (header && !cJSON_IsNull(header)) {
        st = rs_fail(err, RS_ERR_FORMAT, "profil %s : les en-têtes ne sont pas encore gérés", p->id);
        goto done;
    }

    const cJSON *footer = cJSON_GetObjectItemCaseSensitive(j, "footer");
    if (footer && !cJSON_IsNull(footer)) {
        const cJSON *len = cJSON_GetObjectItemCaseSensitive(footer, "length");
        const cJSON *prefix = cJSON_GetObjectItemCaseSensitive(footer, "prefix");
        const cJSON *cookie = cJSON_GetObjectItemCaseSensitive(footer, "cookie");
        const cJSON *fields = cJSON_GetObjectItemCaseSensitive(footer, "fields");
        if (!cJSON_IsNumber(len)) {
            st = rs_fail(err, RS_ERR_FORMAT, "profil %s : longueur du pied manquante", p->id);
            goto done;
        }
        p->has_footer = true;
        p->footer_length = (size_t)len->valuedouble;
        p->footer_prefix = rs_strdup(cJSON_IsString(prefix) ? prefix->valuestring : "");
        p->footer_cookie = rs_strdup(cJSON_IsString(cookie) ? cookie->valuestring : "");
        const cJSON *f;
        cJSON_ArrayForEach(f, fields)
        {
            if (p->field_count == RS_PROFILE_MAX_FIELDS) {
                st = rs_fail(err, RS_ERR_FORMAT, "profil %s : trop de champs", p->id);
                goto done;
            }
            st = parse_field(p->id, f, &p->fields[p->field_count++], err);
            if (st != RS_OK)
                goto done;
        }
        size_t declared = strlen(p->footer_prefix) + 4 * (size_t)p->field_count + strlen(p->footer_cookie);
        if (declared != p->footer_length) {
            st = rs_fail(err, RS_ERR_FORMAT, "profil %s : pied de %zu octets, %zu déclarés", p->id,
                         p->footer_length, declared);
            goto done;
        }
    }

    const cJSON *size = cJSON_GetObjectItemCaseSensitive(j, "size");
    const cJSON *output = cJSON_GetObjectItemCaseSensitive(size, "output");
    p->pad_min = cJSON_IsString(output) && strcmp(output->valuestring, "pad_min") == 0;
    const cJSON *pad_to = cJSON_GetObjectItemCaseSensitive(size, "pad_to");
    const cJSON *pad_byte = cJSON_GetObjectItemCaseSensitive(size, "pad_byte");
    p->pad_to = cJSON_IsNumber(pad_to) ? (size_t)pad_to->valuedouble : 0;
    p->pad_byte = cJSON_IsNumber(pad_byte) ? (uint8_t)pad_byte->valuedouble : 0xFF;

done:
    cJSON_Delete(j);
    if (st != RS_OK)
        rs_profile_free(p);
    return st;
}

void rs_profile_free(rs_profile *p)
{
    free(p->footer_prefix);
    free(p->footer_cookie);
    p->footer_prefix = p->footer_cookie = NULL;
}

/* ---- Conversion -------------------------------------------------------- */

/* DeSmuME's save_types sizes, from index 1 (see profiles/desmume.json). */
static const uint32_t desmume_types[] = {
    512, 8 << 10, 64 << 10, 32 << 10, 256 << 10, 512 << 10,
    1 << 20, 2 << 20, 4 << 20, 8 << 20, 16 << 20, 32 << 20,
};

static uint32_t field_value(const rs_profile_field *f, size_t raw_size)
{
    switch (f->kind) {
    case RS_FIELD_NUMBER:
        return f->number;
    case RS_FIELD_RAW_SIZE:
        return (uint32_t)raw_size;
    case RS_FIELD_DESMUME_SAVE_TYPE:
        for (size_t i = 0; i < sizeof desmume_types / sizeof desmume_types[0]; i++)
            if (desmume_types[i] == raw_size)
                return (uint32_t)i + 1;
        return 0;
    case RS_FIELD_DESMUME_ADDR_SIZE:
        return raw_size <= 512 ? 1 : (raw_size <= (64 << 10) ? 2 : 3);
    }
    return 0;
}

static uint32_t load_le32(const uint8_t *b)
{
    return (uint32_t)b[0] | (uint32_t)b[1] << 8 | (uint32_t)b[2] << 16 | (uint32_t)b[3] << 24;
}

static bool matches(const uint8_t *b, size_t len, size_t at, const char *s)
{
    size_t n = strlen(s);
    return at + n <= len && memcmp(b + at, s, n) == 0;
}

rs_status rs_profile_decode(const rs_profile *p, const uint8_t *file, size_t len, rs_buf *out,
                            rs_error *err)
{
    out->len = 0;
    if (!p->has_footer)
        return rs_buf_append(out, file, len) ? RS_OK : rs_fail(err, RS_ERR_NOMEM, "Mémoire insuffisante");
    if (len < p->footer_length)
        return rs_fail(err, RS_ERR_FORMAT, "%s : fichier trop court pour son pied de %zu octets", p->name,
                       p->footer_length);
    size_t start = len - p->footer_length;
    if (!matches(file, len, start, p->footer_prefix) ||
        !matches(file, len, len - strlen(p->footer_cookie), p->footer_cookie))
        return rs_fail(err, RS_ERR_FORMAT, "%s : pied de fichier introuvable", p->name);
    /* Fixed numeric values (e.g. the version) must match, and the size the
     * footer announces must be the size of the data before it. */
    size_t off = start + strlen(p->footer_prefix);
    for (int i = 0; i < p->field_count; i++, off += 4) {
        const rs_profile_field *f = &p->fields[i];
        uint32_t v = load_le32(file + off);
        if (f->kind == RS_FIELD_NUMBER && v != f->number)
            return rs_fail(err, RS_ERR_FORMAT, "%s : %s inattendu (%u)", p->name, f->name, (unsigned)v);
        if (f->kind == RS_FIELD_RAW_SIZE && strcmp(f->name, "pad_size") == 0 && v != start)
            return rs_fail(err, RS_ERR_FORMAT, "%s : le pied annonce %u octets, le fichier en a %zu",
                           p->name, (unsigned)v, start);
    }
    return rs_buf_append(out, file, start) ? RS_OK : rs_fail(err, RS_ERR_NOMEM, "Mémoire insuffisante");
}

rs_status rs_profile_encode(const rs_profile *p, const uint8_t *raw, size_t len, size_t chip_size,
                            rs_buf *out, rs_error *err)
{
    out->len = 0;
    bool ok = rs_buf_append(out, raw, len);
    if (p->pad_min) {
        size_t target = p->pad_to > chip_size ? p->pad_to : chip_size;
        if (len < target)
            ok = ok && rs_buf_fill(out, p->pad_byte, target - len);
    }
    if (p->has_footer) {
        ok = ok && rs_buf_append(out, p->footer_prefix, strlen(p->footer_prefix));
        for (int i = 0; i < p->field_count; i++) {
            uint32_t v = field_value(&p->fields[i], len);
            uint8_t le[4] = {(uint8_t)v, (uint8_t)(v >> 8), (uint8_t)(v >> 16), (uint8_t)(v >> 24)};
            ok = ok && rs_buf_append(out, le, 4);
        }
        ok = ok && rs_buf_append(out, p->footer_cookie, strlen(p->footer_cookie));
    }
    return ok ? RS_OK : rs_fail(err, RS_ERR_NOMEM, "Mémoire insuffisante");
}

/* ---- Sets of profiles -------------------------------------------------- */

static int compare_names(const void *a, const void *b)
{
    return strcmp(*(char *const *)a, *(char *const *)b);
}

rs_status rs_profiles_load_dir(rs_profiles *set, const char *dir, rs_error *err)
{
    DIR *d = opendir(dir);
    if (!d)
        return rs_fail(err, RS_ERR_NOT_FOUND, "Dossier de profils introuvable : %s", dir);
    char *names[64];
    int n = 0;
    struct dirent *e;
    while ((e = readdir(d)) != NULL && n < 64)
        if (e->d_name[0] != '.' && rs_str_ends_with_ci(e->d_name, ".json"))
            names[n++] = rs_strdup(e->d_name);
    closedir(d);
    qsort(names, (size_t)n, sizeof names[0], compare_names);

    rs_status st = RS_OK;
    for (int i = 0; i < n && st == RS_OK; i++) {
        char path[RS_PATH_MAX];
        rs_path_join(path, sizeof path, dir, names[i]);
        rs_buf b = {0};
        st = rs_read_file(path, &b, err);
        if (st == RS_OK && !rs_buf_terminate(&b))
            st = rs_fail(err, RS_ERR_NOMEM, "Mémoire insuffisante");
        rs_profile p;
        if (st == RS_OK)
            st = rs_profile_parse((const char *)b.data, &p, err);
        rs_buf_free(&b);
        if (st != RS_OK)
            break;
        /* Replace a profile with the same id (SD card overrides). */
        int slot = set->count;
        for (int k = 0; k < set->count; k++)
            if (strcmp(set->items[k].id, p.id) == 0)
                slot = k;
        if (slot == RS_MAX_PROFILES) {
            rs_profile_free(&p);
            st = rs_fail(err, RS_ERR_FORMAT, "Trop de profils dans %s", dir);
            break;
        }
        if (slot < set->count)
            rs_profile_free(&set->items[slot]);
        else
            set->count++;
        set->items[slot] = p;
    }
    for (int i = 0; i < n; i++)
        free(names[i]);
    return st;
}

const rs_profile *rs_profiles_find(const rs_profiles *set, const char *id)
{
    for (int i = 0; i < set->count; i++)
        if (strcmp(set->items[i].id, id) == 0)
            return &set->items[i];
    return NULL;
}

void rs_profiles_free(rs_profiles *set)
{
    for (int i = 0; i < set->count; i++)
        rs_profile_free(&set->items[i]);
    set->count = 0;
}
