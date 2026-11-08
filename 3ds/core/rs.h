/*
 * rs.h - small helpers shared by the whole RomSync core: growable byte
 * buffers, error reporting, strings and files.
 *
 * The core is plain C99 + stdio/dirent so that the same code runs on Linux
 * (tests) and on the 3DS (devkitARM's newlib provides the same functions on
 * the SD card, "sdmc:/").
 */
#ifndef RS_H
#define RS_H

#include <stdarg.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/* ---- Byte buffers ------------------------------------------------------ */

/* A growable array of bytes. Zero-initialise it ({0}) before use and
 * release it with rs_buf_free. */
typedef struct {
    uint8_t *data;
    size_t len;
    size_t cap;
} rs_buf;

/* Appends n bytes; returns false when memory runs out. */
bool rs_buf_append(rs_buf *b, const void *src, size_t n);
/* Appends n copies of byte. */
bool rs_buf_fill(rs_buf *b, uint8_t byte, size_t n);
/* Makes the content a NUL-terminated string (the NUL is not counted). */
bool rs_buf_terminate(rs_buf *b);
void rs_buf_free(rs_buf *b);

/* ---- Errors ------------------------------------------------------------ */

typedef enum {
    RS_OK = 0,
    RS_ERR_OFFLINE,   /* the server could not be reached */
    RS_ERR_API,       /* the server answered with an error (see http_status, code) */
    RS_ERR_IO,        /* a file could not be read or written */
    RS_ERR_NOT_FOUND, /* a file does not exist */
    RS_ERR_FORMAT,    /* malformed JSON, profile, save file... */
    RS_ERR_NOMEM,
    RS_ERR_REFUSED,   /* the sync cannot run (choice needed, unauthorized...) */
} rs_status;

/* Details of the last failure. Functions that can fail take an rs_error*
 * (may be NULL) and return an rs_status. */
typedef struct {
    rs_status status;
    int http_status;    /* RS_ERR_API only */
    char code[32];      /* RS_ERR_API only: "size_mismatch", "unauthorized"... */
    char message[256];  /* French, shown to the user */
} rs_error;

/* Fills err (when not NULL) and returns status. */
rs_status rs_fail(rs_error *err, rs_status status, const char *fmt, ...)
#if defined(__GNUC__)
    __attribute__((format(printf, 3, 4)))
#endif
    ;

/* ---- Strings ----------------------------------------------------------- */

/* Copies src into dst (size bytes) and always NUL-terminates. */
void rs_strlcpy(char *dst, const char *src, size_t size);
/* malloc'ed copy of s (NULL stays NULL). */
char *rs_strdup(const char *s);
bool rs_str_ends_with_ci(const char *s, const char *suffix);
/* Writes n bytes as 2n lowercase hex characters plus a NUL. */
void rs_hex(const uint8_t *bytes, size_t n, char *out);

/* ---- Paths and files --------------------------------------------------- */

#define RS_PATH_MAX 512

/* out = a + "/" + b (without doubling the slash). */
void rs_path_join(char *out, size_t size, const char *a, const char *b);
/* Directory part of path ("sdmc:/roms/x.nds" -> "sdmc:/roms"). */
void rs_dirname(const char *path, char *out, size_t size);
/* File name part of path (points inside path). */
const char *rs_basename(const char *path);

bool rs_file_exists(const char *path);
bool rs_dir_exists(const char *path);
/* Creates path and its missing parents. */
rs_status rs_mkdirs(const char *path, rs_error *err);
/* Reads a whole file. RS_ERR_NOT_FOUND when it does not exist. */
rs_status rs_read_file(const char *path, rs_buf *out, rs_error *err);
/* Writes a file through a temporary copy, so that a crash never leaves a
 * half-written file behind. Creates the parent folders. */
rs_status rs_write_file_atomic(const char *path, const void *data, size_t len, rs_error *err);
rs_status rs_copy_file(const char *from, const char *to, rs_error *err);

#endif
