/*
 * rs.c - buffers, errors, strings and file helpers (see rs.h).
 */
#include "rs.h"

#include <ctype.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>

/* ---- Byte buffers ------------------------------------------------------ */

static bool reserve(rs_buf *b, size_t extra)
{
    if (b->len + extra <= b->cap)
        return true;
    size_t cap = b->cap ? b->cap : 256;
    while (cap < b->len + extra)
        cap *= 2;
    uint8_t *p = realloc(b->data, cap);
    if (!p)
        return false;
    b->data = p;
    b->cap = cap;
    return true;
}

bool rs_buf_append(rs_buf *b, const void *src, size_t n)
{
    if (n == 0)
        return true;
    if (!reserve(b, n))
        return false;
    memcpy(b->data + b->len, src, n);
    b->len += n;
    return true;
}

bool rs_buf_fill(rs_buf *b, uint8_t byte, size_t n)
{
    if (n == 0)
        return true;
    if (!reserve(b, n))
        return false;
    memset(b->data + b->len, byte, n);
    b->len += n;
    return true;
}

bool rs_buf_terminate(rs_buf *b)
{
    if (!reserve(b, 1))
        return false;
    b->data[b->len] = 0;
    return true;
}

void rs_buf_free(rs_buf *b)
{
    free(b->data);
    b->data = NULL;
    b->len = b->cap = 0;
}

/* ---- Errors ------------------------------------------------------------ */

rs_status rs_fail(rs_error *err, rs_status status, const char *fmt, ...)
{
    if (err) {
        err->status = status;
        err->http_status = 0;
        err->code[0] = 0;
        va_list ap;
        va_start(ap, fmt);
        vsnprintf(err->message, sizeof err->message, fmt, ap);
        va_end(ap);
    }
    return status;
}

/* ---- Strings ----------------------------------------------------------- */

void rs_strlcpy(char *dst, const char *src, size_t size)
{
    if (size == 0)
        return;
    size_t n = strlen(src);
    if (n >= size)
        n = size - 1;
    memcpy(dst, src, n);
    dst[n] = 0;
}

char *rs_strdup(const char *s)
{
    if (!s)
        return NULL;
    size_t n = strlen(s) + 1;
    char *p = malloc(n);
    if (p)
        memcpy(p, s, n);
    return p;
}

bool rs_str_ends_with_ci(const char *s, const char *suffix)
{
    size_t n = strlen(s), m = strlen(suffix);
    if (m > n)
        return false;
    for (size_t i = 0; i < m; i++)
        if (tolower((unsigned char)s[n - m + i]) != tolower((unsigned char)suffix[i]))
            return false;
    return true;
}

void rs_hex(const uint8_t *bytes, size_t n, char *out)
{
    static const char digits[] = "0123456789abcdef";
    for (size_t i = 0; i < n; i++) {
        out[2 * i] = digits[bytes[i] >> 4];
        out[2 * i + 1] = digits[bytes[i] & 15];
    }
    out[2 * n] = 0;
}

/* ---- Paths and files --------------------------------------------------- */

void rs_path_join(char *out, size_t size, const char *a, const char *b)
{
    size_t n = strlen(a);
    while (*b == '/')
        b++;
    if (n > 0 && a[n - 1] == '/')
        snprintf(out, size, "%s%s", a, b);
    else
        snprintf(out, size, "%s/%s", a, b);
}

void rs_dirname(const char *path, char *out, size_t size)
{
    const char *slash = strrchr(path, '/');
    if (!slash) {
        rs_strlcpy(out, ".", size);
        return;
    }
    size_t n = (size_t)(slash - path);
    /* Keep the slash of a root such as "/" or "sdmc:/". */
    if (n == 0 || path[n - 1] == ':')
        n++;
    if (n >= size)
        n = size - 1;
    memcpy(out, path, n);
    out[n] = 0;
}

const char *rs_basename(const char *path)
{
    const char *slash = strrchr(path, '/');
    return slash ? slash + 1 : path;
}

bool rs_file_exists(const char *path)
{
    struct stat st;
    return stat(path, &st) == 0 && S_ISREG(st.st_mode);
}

bool rs_dir_exists(const char *path)
{
    struct stat st;
    return stat(path, &st) == 0 && S_ISDIR(st.st_mode);
}

rs_status rs_mkdirs(const char *path, rs_error *err)
{
    char tmp[RS_PATH_MAX];
    rs_strlcpy(tmp, path, sizeof tmp);
    size_t n = strlen(tmp);
    while (n > 1 && tmp[n - 1] == '/')
        tmp[--n] = 0;
    /* Create each level in turn. Skip the device part ("sdmc:"). */
    char *p = strchr(tmp, ':');
    p = p ? p + 1 : tmp;
    for (p++; *p; p++) {
        if (*p != '/')
            continue;
        *p = 0;
        if (!rs_dir_exists(tmp) && mkdir(tmp, 0777) != 0 && errno != EEXIST)
            return rs_fail(err, RS_ERR_IO, "Impossible de créer %s", tmp);
        *p = '/';
    }
    if (!rs_dir_exists(tmp) && mkdir(tmp, 0777) != 0 && errno != EEXIST)
        return rs_fail(err, RS_ERR_IO, "Impossible de créer %s", tmp);
    return RS_OK;
}

rs_status rs_read_file(const char *path, rs_buf *out, rs_error *err)
{
    FILE *f = fopen(path, "rb");
    if (!f) {
        if (errno == ENOENT || !rs_file_exists(path))
            return rs_fail(err, RS_ERR_NOT_FOUND, "%s introuvable", path);
        return rs_fail(err, RS_ERR_IO, "Lecture impossible : %s", path);
    }
    /* Read straight into the buffer, 16 KiB at a time: a chunk on the stack
     * would eat the 3DS's small stack. */
    out->len = 0;
    for (;;) {
        if (!reserve(out, 16 * 1024)) {
            fclose(f);
            return rs_fail(err, RS_ERR_NOMEM, "Mémoire insuffisante pour lire %s", path);
        }
        size_t n = fread(out->data + out->len, 1, out->cap - out->len, f);
        if (n == 0)
            break;
        out->len += n;
    }
    bool failed = ferror(f);
    fclose(f);
    if (failed)
        return rs_fail(err, RS_ERR_IO, "Lecture impossible : %s", path);
    return RS_OK;
}

rs_status rs_write_file_atomic(const char *path, const void *data, size_t len, rs_error *err)
{
    char dir[RS_PATH_MAX], tmp[RS_PATH_MAX];
    rs_dirname(path, dir, sizeof dir);
    rs_status st = rs_mkdirs(dir, err);
    if (st != RS_OK)
        return st;
    snprintf(tmp, sizeof tmp, "%s.tmp", path);
    FILE *f = fopen(tmp, "wb");
    if (!f)
        return rs_fail(err, RS_ERR_IO, "Écriture impossible : %s", tmp);
    bool ok = fwrite(data, 1, len, f) == len;
    ok = (fclose(f) == 0) && ok;
    if (!ok) {
        remove(tmp);
        return rs_fail(err, RS_ERR_IO, "Écriture impossible : %s", tmp);
    }
    if (rename(tmp, path) != 0) {
        /* 3DS: the SD card driver refuses to rename over an existing file,
         * unlike Linux. Remove the old file first; the new content is
         * already complete in the temporary file. */
        remove(path);
        if (rename(tmp, path) != 0) {
            remove(tmp);
            return rs_fail(err, RS_ERR_IO, "Écriture impossible : %s", path);
        }
    }
    return RS_OK;
}

rs_status rs_copy_file(const char *from, const char *to, rs_error *err)
{
    rs_buf b = {0};
    rs_status st = rs_read_file(from, &b, err);
    if (st == RS_OK)
        st = rs_write_file_atomic(to, b.data, b.len, err);
    rs_buf_free(&b);
    return st;
}
