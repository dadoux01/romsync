/*
 * tree.c - saves made of a folder (see tree.h).
 */
#include "tree.h"

#include <dirent.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include "msg.h"

/* ---- Entries ----------------------------------------------------------- */

void rs_tree_free(rs_tree *t)
{
    for (int i = 0; i < t->count; i++) {
        free(t->items[i].path);
        free(t->items[i].data);
    }
    free(t->items);
    memset(t, 0, sizeof *t);
}

bool rs_tree_add(rs_tree *t, const char *path, const uint8_t *data, size_t size)
{
    if (t->count == t->cap) {
        int cap = t->cap ? t->cap * 2 : 16;
        rs_tree_entry *grown = realloc(t->items, (size_t)cap * sizeof *grown);
        if (!grown)
            return false;
        t->items = grown;
        t->cap = cap;
    }
    rs_tree_entry *e = &t->items[t->count];
    memset(e, 0, sizeof *e);
    e->path = rs_strdup(path);
    if (data && size) {
        e->data = malloc(size);
        if (e->data)
            memcpy(e->data, data, size);
    }
    if (!e->path || (data && size && !e->data)) {
        free(e->path);
        free(e->data);
        return false;
    }
    e->size = size;
    t->count++;
    return true;
}

static bool is_dir_path(const char *p)
{
    size_t n = strlen(p);
    return n > 0 && p[n - 1] == '/';
}

/* A relative path without empty, "." or ".." components. */
static bool valid_path(const char *p)
{
    size_t n = strlen(p);
    if (n == 0 || p[0] == '/')
        return false;
    if (is_dir_path(p))
        n--;
    size_t start = 0;
    for (size_t i = 0; i <= n; i++) {
        if (i == n || p[i] == '/') {
            size_t len = i - start;
            if (len == 0 || (len == 1 && p[start] == '.') || (len == 2 && p[start] == '.' && p[start + 1] == '.'))
                return false;
            start = i + 1;
        }
    }
    return true;
}

static int compare_paths(const void *a, const void *b)
{
    /* Byte order: strcmp compares unsigned chars. */
    return strcmp(((const rs_tree_entry *)a)->path, ((const rs_tree_entry *)b)->path);
}

/* Path without its final "/" (to find a file and a folder of the same name). */
static size_t key_length(const char *p)
{
    size_t n = strlen(p);
    return is_dir_path(p) ? n - 1 : n;
}

static int find(const rs_tree *t, const char *path)
{
    size_t n = key_length(path);
    for (int i = 0; i < t->count; i++)
        if (key_length(t->items[i].path) == n && strncmp(t->items[i].path, path, n) == 0)
            return i;
    return -1;
}

/* ---- Canonical archive ------------------------------------------------- */

static void octal(uint8_t *dst, size_t width, unsigned long long n)
{
    char tmp[24];
    snprintf(tmp, sizeof tmp, "%0*llo", (int)(width - 1), n);
    memcpy(dst, tmp, width - 1);
}

static bool header(const char *path, bool dir, size_t size, uint8_t h[512])
{
    size_t len = strlen(path);
    size_t cut = 0;
    bool split = len > 100;
    if (split) {
        bool found = false;
        for (size_t i = len; i-- > 0;) {
            if (path[i] == '/' && i <= 155 && len - i - 1 <= 100 && len - i - 1 > 0) {
                cut = i;
                found = true;
                break;
            }
        }
        if (!found)
            return false;
    }
    memset(h, 0, 512);
    if (split) {
        memcpy(h, path + cut + 1, len - cut - 1);
        memcpy(h + 345, path, cut);
    } else {
        memcpy(h, path, len);
    }
    octal(h + 100, 8, dir ? 0755 : 0644);
    octal(h + 108, 8, 0);
    octal(h + 116, 8, 0);
    octal(h + 124, 12, dir ? 0 : size);
    octal(h + 136, 12, 0);
    memset(h + 148, ' ', 8);
    h[156] = dir ? '5' : '0';
    memcpy(h + 257, "ustar", 6);
    memcpy(h + 263, "00", 2);
    unsigned sum = 0;
    for (int i = 0; i < 512; i++)
        sum += h[i];
    char chk[8];
    snprintf(chk, sizeof chk, "%06o", sum);
    memcpy(h + 148, chk, 6);
    h[154] = 0;
    h[155] = ' ';
    return true;
}

rs_status rs_tree_archive(const rs_tree *t, rs_buf *out, rs_error *err)
{
    out->len = 0;
    /* Entries plus their missing parent folders, without the data (which
     * stays in t). */
    rs_tree all = {0};
    rs_status st = RS_OK;
    char path[RS_PATH_MAX];
    for (int i = 0; i < t->count && st == RS_OK; i++) {
        const char *p = t->items[i].path;
        if (!valid_path(p) || strlen(p) >= sizeof path || (is_dir_path(p) && t->items[i].size)) {
            st = rs_fail(err, RS_ERR_FORMAT, RS_TR(TREE_INVALID_PATH), p);
            break;
        }
        /* Parents first: "a/", "a/b/"... */
        for (const char *s = strchr(p, '/'); s && s[1]; s = strchr(s + 1, '/')) {
            size_t n = (size_t)(s - p) + 1;
            memcpy(path, p, n);
            path[n] = 0;
            int parent = find(&all, path);
            if (parent >= 0 && !is_dir_path(all.items[parent].path))
                st = rs_fail(err, RS_ERR_FORMAT, RS_TR(TREE_INVALID_PATH), p); /* a file of that name */
            else if (parent < 0 && !rs_tree_add(&all, path, NULL, 0))
                st = rs_fail(err, RS_ERR_NOMEM, RS_TR(NOMEM));
        }
        if (st != RS_OK)
            break;
        int prev = find(&all, p);
        if (prev >= 0 && !(is_dir_path(all.items[prev].path) && is_dir_path(p))) {
            st = rs_fail(err, RS_ERR_FORMAT, RS_TR(TREE_INVALID_PATH), p);
            break;
        }
        if (st == RS_OK && prev < 0 && !rs_tree_add(&all, p, NULL, 0))
            st = rs_fail(err, RS_ERR_NOMEM, RS_TR(NOMEM));
        /* A file keeps the index of its entry in t (its data stays there). */
        if (st == RS_OK && prev < 0)
            all.items[all.count - 1].mtime = i;
    }
    if (st == RS_OK) {
        if (all.count > 0)
            qsort(all.items, (size_t)all.count, sizeof *all.items, compare_paths);
        uint8_t h[512];
        static const uint8_t zeros[1024];
        for (int i = 0; i < all.count && st == RS_OK; i++) {
            const char *p = all.items[i].path;
            bool dir = is_dir_path(p);
            const rs_tree_entry *src = dir ? NULL : &t->items[all.items[i].mtime];
            size_t size = src ? src->size : 0;
            if (!header(p, dir, size, h)) {
                st = rs_fail(err, RS_ERR_FORMAT, RS_TR(TREE_INVALID_PATH), p);
                break;
            }
            if (!rs_buf_append(out, h, 512) || (size && !rs_buf_append(out, src->data, size)) ||
                !rs_buf_append(out, zeros, (512 - size % 512) % 512))
                st = rs_fail(err, RS_ERR_NOMEM, RS_TR(NOMEM));
        }
        if (st == RS_OK && !rs_buf_append(out, zeros, 1024))
            st = rs_fail(err, RS_ERR_NOMEM, RS_TR(NOMEM));
    }
    rs_tree_free(&all);
    return st;
}

rs_status rs_tree_parse(const uint8_t *tar, size_t len, rs_tree *out, rs_error *err)
{
    memset(out, 0, sizeof *out);
    size_t off = 0;
    char path[RS_PATH_MAX];
    while (off + 512 <= len) {
        const uint8_t *h = tar + off;
        bool empty = true;
        for (int i = 0; i < 512 && empty; i++)
            empty = h[i] == 0;
        if (empty)
            return RS_OK;
        char name[101] = "", prefix[156] = "", size_text[13] = "";
        memcpy(name, h, 100);
        memcpy(prefix, h + 345, 155);
        memcpy(size_text, h + 124, 12);
        if (prefix[0])
            snprintf(path, sizeof path, "%s/%s", prefix, name);
        else
            snprintf(path, sizeof path, "%s", name);
        char *end;
        unsigned long long size = strtoull(size_text, &end, 8);
        off += 512;
        bool dir = h[156] == '5';
        if ((!dir && h[156] != '0' && h[156] != 0) || off + size > len) {
            rs_tree_free(out);
            return rs_fail(err, RS_ERR_FORMAT, RS_TR(TREE_BAD_ARCHIVE));
        }
        if (dir && !is_dir_path(path))
            strncat(path, "/", sizeof path - strlen(path) - 1);
        if (!rs_tree_add(out, path, dir ? NULL : tar + off, dir ? 0 : (size_t)size)) {
            rs_tree_free(out);
            return rs_fail(err, RS_ERR_NOMEM, RS_TR(NOMEM));
        }
        off += (size_t)((size + 511) / 512 * 512);
    }
    rs_tree_free(out);
    return rs_fail(err, RS_ERR_FORMAT, RS_TR(TREE_BAD_ARCHIVE));
}

/* ---- Folders on disk --------------------------------------------------- */

/* Adds everything under base/rel to t (with the content when with_data). */
static rs_status scan(const char *base, const char *rel, rs_tree *t, bool with_data, rs_error *err)
{
    char dir[RS_PATH_MAX];
    rs_path_join(dir, sizeof dir, base, rel);
    DIR *d = opendir(dir);
    if (!d)
        return rs_fail(err, RS_ERR_IO, RS_TR(READ_FAILED), dir);
    rs_status st = RS_OK;
    struct dirent *de;
    while (st == RS_OK && (de = readdir(d))) {
        if (strcmp(de->d_name, ".") == 0 || strcmp(de->d_name, "..") == 0)
            continue;
        char child[RS_PATH_MAX], full[RS_PATH_MAX];
        if (rel[0])
            snprintf(child, sizeof child, "%s/%s", rel, de->d_name);
        else
            snprintf(child, sizeof child, "%s", de->d_name);
        rs_path_join(full, sizeof full, base, child);
        struct stat s;
        if (stat(full, &s) != 0) {
            st = rs_fail(err, RS_ERR_IO, RS_TR(READ_FAILED), full);
        } else if (S_ISDIR(s.st_mode)) {
            char path[RS_PATH_MAX];
            snprintf(path, sizeof path, "%s/", child);
            st = rs_tree_add(t, path, NULL, 0) ? scan(base, child, t, with_data, err)
                                                : rs_fail(err, RS_ERR_NOMEM, RS_TR(NOMEM));
        } else {
            rs_buf b = {0};
            if (with_data)
                st = rs_read_file(full, &b, err);
            if (st == RS_OK && !rs_tree_add(t, child, b.data, with_data ? b.len : (size_t)s.st_size))
                st = rs_fail(err, RS_ERR_NOMEM, RS_TR(NOMEM));
            if (st == RS_OK) {
                t->items[t->count - 1].mtime = (long long)s.st_mtime;
                t->items[t->count - 1].size = with_data ? b.len : (size_t)s.st_size;
            }
            rs_buf_free(&b);
        }
    }
    closedir(d);
    return st;
}

/* "path size mtime" of every entry, sorted: equal snapshots, same folder. */
static rs_status snapshot(const char *dir, rs_buf *out, rs_error *err)
{
    rs_tree t = {0};
    out->len = 0;
    rs_status st = scan(dir, "", &t, false, err);
    if (st == RS_OK && t.count > 0) {
        qsort(t.items, (size_t)t.count, sizeof *t.items, compare_paths);
    }
    if (st == RS_OK) {
        char line[RS_PATH_MAX + 48];
        for (int i = 0; i < t.count && st == RS_OK; i++) {
            int n = snprintf(line, sizeof line, "%s %zu %lld\n", t.items[i].path, t.items[i].size, t.items[i].mtime);
            if (!rs_buf_append(out, line, (size_t)n))
                st = rs_fail(err, RS_ERR_NOMEM, RS_TR(NOMEM));
        }
    }
    rs_tree_free(&t);
    return st;
}

static bool same(const rs_buf *a, const rs_buf *b)
{
    return a->len == b->len && (a->len == 0 || memcmp(a->data, b->data, a->len) == 0);
}

rs_status rs_tree_read_dir(const char *dir, rs_buf *out, bool *exists, long long *newest, rs_error *err)
{
    out->len = 0;
    *exists = rs_dir_exists(dir);
    if (newest)
        *newest = 0;
    if (!*exists)
        return RS_OK;
    rs_buf before = {0}, after = {0};
    rs_status st = RS_OK;
    for (int attempt = 0; attempt < 5; attempt++) {
        rs_tree t = {0};
        st = snapshot(dir, &before, err);
        if (st == RS_OK)
            st = scan(dir, "", &t, true, err);
        if (st == RS_OK)
            st = snapshot(dir, &after, err);
        if (st == RS_OK && same(&before, &after)) {
            for (int i = 0; newest && i < t.count; i++)
                if (t.items[i].mtime > *newest)
                    *newest = t.items[i].mtime;
            st = rs_tree_archive(&t, out, err);
            rs_tree_free(&t);
            rs_buf_free(&before);
            rs_buf_free(&after);
            return st;
        }
        rs_tree_free(&t);
        if (st != RS_OK)
            break;
    }
    rs_buf_free(&before);
    rs_buf_free(&after);
    return st != RS_OK ? st : rs_fail(err, RS_ERR_IO, RS_TR(TREE_CHANGING), dir);
}

rs_status rs_tree_remove(const char *dir, rs_error *err)
{
    rs_tree t = {0};
    rs_status st = scan(dir, "", &t, false, err);
    if (st == RS_OK) {
        /* Deepest first: reverse byte order puts a folder after its content. */
        if (t.count > 0)
            qsort(t.items, (size_t)t.count, sizeof *t.items, compare_paths);
        char full[RS_PATH_MAX];
        for (int i = t.count; i-- > 0 && st == RS_OK;) {
            rs_path_join(full, sizeof full, dir, t.items[i].path);
            if (is_dir_path(full))
                full[strlen(full) - 1] = 0;
            if ((is_dir_path(t.items[i].path) ? rmdir(full) : remove(full)) != 0)
                st = rs_fail(err, RS_ERR_IO, RS_TR(WRITE_FAILED), full);
        }
    }
    rs_tree_free(&t);
    if (st == RS_OK && rmdir(dir) != 0)
        st = rs_fail(err, RS_ERR_IO, RS_TR(WRITE_FAILED), dir);
    return st;
}

rs_status rs_tree_write_dir(const char *dir, const uint8_t *tar, size_t len, rs_error *err)
{
    rs_tree t;
    rs_status st = rs_tree_parse(tar, len, &t, err);
    if (st != RS_OK)
        return st;
    char fresh[RS_PATH_MAX], old[RS_PATH_MAX], full[RS_PATH_MAX];
    snprintf(fresh, sizeof fresh, "%s.romsync-new", dir);
    snprintf(old, sizeof old, "%s.romsync-old", dir);
    if (rs_dir_exists(fresh))
        st = rs_tree_remove(fresh, err);
    if (st == RS_OK && rs_dir_exists(old))
        st = rs_tree_remove(old, err);
    if (st == RS_OK)
        st = rs_mkdirs(fresh, err);
    for (int i = 0; i < t.count && st == RS_OK; i++) {
        if (!valid_path(t.items[i].path)) {
            st = rs_fail(err, RS_ERR_FORMAT, RS_TR(TREE_INVALID_PATH), t.items[i].path);
            break;
        }
        rs_path_join(full, sizeof full, fresh, t.items[i].path);
        if (is_dir_path(t.items[i].path))
            st = rs_mkdirs(full, err);
        else
            st = rs_write_file_atomic(full, t.items[i].data ? t.items[i].data : (const uint8_t *)"", t.items[i].size,
                                      err);
    }
    rs_tree_free(&t);
    if (st != RS_OK)
        return st;
    /* The SD card of the 3DS refuses to rename over an existing entry: the
     * current folder moves aside first. */
    bool had_old = rs_dir_exists(dir);
    if (had_old && rename(dir, old) != 0)
        return rs_fail(err, RS_ERR_IO, RS_TR(WRITE_FAILED), dir);
    if (rename(fresh, dir) != 0) {
        if (had_old)
            rename(old, dir);
        return rs_fail(err, RS_ERR_IO, RS_TR(WRITE_FAILED), dir);
    }
    return had_old ? rs_tree_remove(old, err) : RS_OK;
}
