/*
 * nds.c - ROM header parsing and game identifiers (see nds.h).
 */
#include "nds.h"

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "sha.h"

/* Copies the printable ASCII bytes of src, dropping the others (NUL
 * padding...), then trims spaces, like romsync_core's NdsHeader. */
static void ascii_field(const uint8_t *src, size_t n, char *out)
{
    size_t k = 0;
    for (size_t i = 0; i < n; i++)
        if (src[i] >= 0x20 && src[i] < 0x7F)
            out[k++] = (char)src[i];
    out[k] = 0;
    while (k > 0 && out[k - 1] == ' ')
        out[--k] = 0;
    size_t start = 0;
    while (out[start] == ' ')
        start++;
    memmove(out, out + start, k - start + 1);
}

bool rs_nds_parse(const uint8_t *b, size_t len, rs_nds_header *out)
{
    if (len < RS_NDS_HEADER_LEN)
        return false;
    ascii_field(b + 0x000, 12, out->title);
    /* The game code is kept as is (4 bytes): non-printable bytes become
     * '?', which makes it invalid. */
    for (int i = 0; i < 4; i++) {
        uint8_t c = b[0x00C + i];
        out->game_code[i] = (c >= 0x20 && c < 0x7F) ? (char)c : '?';
    }
    out->game_code[4] = 0;
    ascii_field(b + 0x010, 2, out->maker_code);
    out->unit_code = b[0x012];
    out->rom_version = b[0x01E];
    return true;
}

static bool is_code_char(char c)
{
    return (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9');
}

bool rs_nds_has_valid_code(const rs_nds_header *h)
{
    for (int i = 0; i < 4; i++)
        if (!is_code_char(h->game_code[i]))
            return false;
    return strcmp(h->game_code, "0000") != 0;
}

bool rs_game_id_valid(const char *id)
{
    size_t n = strlen(id);
    if (n == 4) {
        for (int i = 0; i < 4; i++)
            if (!is_code_char(id[i]))
                return false;
        return true;
    }
    if (n == 42 && id[0] == 'h' && id[1] == ':') {
        for (size_t i = 2; i < n; i++)
            if (!((id[i] >= '0' && id[i] <= '9') || (id[i] >= 'a' && id[i] <= 'f')))
                return false;
        return true;
    }
    if (n >= 3 && n <= 34 && id[0] == 'x' && id[1] == ':') {
        for (size_t i = 2; i < n; i++)
            if (!((id[i] >= 'a' && id[i] <= 'z') || (id[i] >= '0' && id[i] <= '9') || id[i] == '-'))
                return false;
        return true;
    }
    return false;
}

bool rs_game_id_custom(const char *name, char *out, size_t size)
{
    char id[64] = "x:";
    size_t k = 2;
    /* Trim, lower-case, and turn each run of spaces or underscores into a
     * single dash. */
    while (*name && isspace((unsigned char)*name))
        name++;
    size_t n = strlen(name);
    while (n > 0 && isspace((unsigned char)name[n - 1]))
        n--;
    for (size_t i = 0; i < n; i++) {
        unsigned char c = (unsigned char)name[i];
        if (isspace(c) || c == '_') {
            while (i + 1 < n && (isspace((unsigned char)name[i + 1]) || name[i + 1] == '_'))
                i++;
            c = '-';
        } else if (c >= 'A' && c <= 'Z') {
            c = (unsigned char)(c - 'A' + 'a');
        }
        if (k + 1 >= sizeof id)
            return false;
        id[k++] = (char)c;
    }
    id[k] = 0;
    if (!rs_game_id_valid(id) || strlen(id) + 1 > size)
        return false;
    rs_strlcpy(out, id, size);
    return true;
}

rs_status rs_rom_identify_header(const char *path, rs_nds_header *header, rs_error *err)
{
    FILE *f = fopen(path, "rb");
    if (!f)
        return rs_fail(err, RS_ERR_IO, "Lecture impossible : %s", path);
    uint8_t buf[RS_NDS_HEADER_LEN];
    size_t n = fread(buf, 1, sizeof buf, f);
    fclose(f);
    if (!rs_nds_parse(buf, n, header))
        return rs_fail(err, RS_ERR_FORMAT, "%s : en-tête de ROM trop court", rs_basename(path));
    return RS_OK;
}

rs_status rs_rom_identify(const char *path, rs_nds_header *header, char id[RS_GAME_ID_MAX],
                          rs_error *err)
{
    rs_status st = rs_rom_identify_header(path, header, err);
    if (st != RS_OK)
        return st;
    if (rs_nds_has_valid_code(header)) {
        rs_strlcpy(id, header->game_code, RS_GAME_ID_MAX);
        return RS_OK;
    }
    FILE *f = fopen(path, "rb");
    if (!f)
        return rs_fail(err, RS_ERR_IO, "Lecture impossible : %s", path);
    /* On the heap: the 3DS stack is small. */
    enum { CHUNK = 16 * 1024 };
    uint8_t *buf = malloc(CHUNK);
    if (!buf) {
        fclose(f);
        return rs_fail(err, RS_ERR_NOMEM, "Mémoire insuffisante");
    }
    /* Homebrew: identify the ROM by the SHA-1 of the whole file, read in
     * chunks so that a large file never sits in memory. */
    rs_sha1 c;
    rs_sha1_init(&c);
    size_t n;
    while ((n = fread(buf, 1, CHUNK, f)) > 0)
        rs_sha1_update(&c, buf, n);
    bool failed = ferror(f);
    fclose(f);
    free(buf);
    if (failed)
        return rs_fail(err, RS_ERR_IO, "Lecture impossible : %s", path);
    uint8_t d[20];
    rs_sha1_final(&c, d);
    id[0] = 'h';
    id[1] = ':';
    rs_hex(d, sizeof d, id + 2);
    return RS_OK;
}
