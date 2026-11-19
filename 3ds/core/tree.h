/*
 * tree.h - saves made of a folder (docs/SPEC.md, "Saves en dossier"): the
 * canonical archive of a folder, byte for byte the server's and
 * romsync_core's (testdata/tree), read from and written to a folder.
 */
#ifndef RS_TREE_H
#define RS_TREE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "rs.h"

/* A file or a folder of a save; a folder's path ends with "/". */
typedef struct {
    char *path;    /* malloc'ed, relative, "/"-separated */
    uint8_t *data; /* malloc'ed content of a file, NULL for a folder */
    size_t size;
    long long mtime; /* modification date when read from disk (seconds) */
} rs_tree_entry;

typedef struct {
    rs_tree_entry *items;
    int count;
    int cap;
} rs_tree;

void rs_tree_free(rs_tree *t);
/* Adds a copy of an entry. Returns false when memory runs out. */
bool rs_tree_add(rs_tree *t, const char *path, const uint8_t *data, size_t size);

/* The canonical archive of t's entries, in any order: missing parent
 * folders are added, invalid paths and duplicates refused. */
rs_status rs_tree_archive(const rs_tree *t, rs_buf *out, rs_error *err);
/* The entries of a ustar archive (the canonical one of the server). */
rs_status rs_tree_parse(const uint8_t *tar, size_t len, rs_tree *out, rs_error *err);

/* Reads the folder dir as its canonical archive, only when nothing changes
 * during the read; *exists is false (and out empty) when the folder does
 * not exist. *newest is the date of its newest file. */
rs_status rs_tree_read_dir(const char *dir, rs_buf *out, bool *exists, long long *newest, rs_error *err);
/* Replaces the folder dir by the content of an archive: written in
 * "<dir>.romsync-new", then swapped in; the previous folder comes back on a
 * failure of the swap. */
rs_status rs_tree_write_dir(const char *dir, const uint8_t *tar, size_t len, rs_error *err);
/* Removes a folder and everything in it. */
rs_status rs_tree_remove(const char *dir, rs_error *err);

#endif
