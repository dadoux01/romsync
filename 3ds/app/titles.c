/*
 * titles.c - the 3DS games of the console and their save archives (see
 * titles.h). The calls follow Checkpoint (3ds/source/archive.cpp, io.cpp,
 * fsstream.cpp, smdh.cpp, titleprobe.cpp).
 */
#include "titles.h"
#include "text.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

#include "../core/cp437.h"
#include "../core/tree.h"

/* High half of the title ID of games (docs/SPEC.md, "Jeux 3DS"). */
#define GAME_HIGH 0x00040000u

/* ---- Paths ------------------------------------------------------------- */

/* A path of a save archive: "/" + the relative UTF-8 path, in UTF-16 (as
 * Checkpoint, which only uses UTF-16 paths). A folder's final "/" is
 * dropped. */
typedef struct {
    uint16_t units[RS_PATH_MAX];
} ctr_path;

static FS_Path make_path(ctr_path *p, const char *rel)
{
    char utf8[RS_PATH_MAX];
    snprintf(utf8, sizeof utf8, "/%s", rel);
    size_t n = strlen(utf8);
    if (n > 1 && utf8[n - 1] == '/')
        utf8[--n] = 0;
    ssize_t units = utf8_to_utf16(p->units, (const uint8_t *)utf8, RS_PATH_MAX - 1);
    if (units < 0)
        units = 0;
    p->units[units] = 0;
    return (FS_Path){PATH_UTF16, (u32)((units + 1) * 2), p->units};
}

static void utf16_to_string(const uint16_t *in, char *out, size_t size)
{
    ssize_t n = utf16_to_utf8((uint8_t *)out, in, size - 1);
    out[n > 0 ? (size_t)n : 0] = 0;
}

/* ---- Save archives ----------------------------------------------------- */

static Result open_save(const ctr_title *t, FS_Archive *arch)
{
    const u32 path[3] = {t->media, (u32)t->id, (u32)(t->id >> 32)};
    return FSUSER_OpenArchive(arch, ARCHIVE_USER_SAVEDATA, (FS_Path){PATH_BINARY, sizeof path, path});
}

static rs_status read_file(FS_Archive arch, const char *rel, uint8_t **data, size_t *size, rs_error *err)
{
    ctr_path p;
    Handle fh = 0;
    *data = NULL;
    *size = 0;
    Result rc = FSUSER_OpenFile(&fh, arch, make_path(&p, rel), FS_OPEN_READ, 0);
    u64 len = 0;
    if (R_SUCCEEDED(rc))
        rc = FSFILE_GetSize(fh, &len);
    if (R_SUCCEEDED(rc) && len) {
        *data = malloc((size_t)len);
        u32 got = 0;
        rc = *data ? FSFILE_Read(fh, &got, 0, *data, (u32)len) : -1;
        if (R_SUCCEEDED(rc) && got != len)
            rc = -1;
    }
    if (fh)
        FSFILE_Close(fh);
    if (R_FAILED(rc)) {
        free(*data);
        *data = NULL;
        return rs_fail(err, RS_ERR_IO, RS_TR(CTR_SAVE_READ), (unsigned long)rc);
    }
    *size = (size_t)len;
    return RS_OK;
}

/* Adds the folder rel ("" for the root) and everything in it to t. With
 * contents false, files are added without their data (sizes only). */
static rs_status walk(FS_Archive arch, const char *rel, bool contents, rs_tree *t, u64 *total, rs_error *err)
{
    ctr_path p;
    Handle dh;
    Result rc = FSUSER_OpenDirectory(&dh, arch, make_path(&p, rel));
    if (R_FAILED(rc))
        return rs_fail(err, RS_ERR_IO, RS_TR(CTR_SAVE_READ), (unsigned long)rc);
    rs_status st = RS_OK;
    for (;;) {
        FS_DirectoryEntry ent;
        u32 n = 0;
        rc = FSDIR_Read(dh, &n, 1, &ent);
        if (R_FAILED(rc)) {
            st = rs_fail(err, RS_ERR_IO, RS_TR(CTR_SAVE_READ), (unsigned long)rc);
            break;
        }
        if (n == 0)
            break;
        char name[RS_PATH_MAX], child[RS_PATH_MAX];
        utf16_to_string(ent.name, name, sizeof name);
        bool dir = ent.attributes & FS_ATTRIBUTE_DIRECTORY;
        snprintf(child, sizeof child, "%s%s%s", rel, name, dir ? "/" : "");
        if (dir) {
            if (!rs_tree_add(t, child, NULL, 0)) {
                st = rs_fail(err, RS_ERR_NOMEM, RS_TR(NOMEM));
                break;
            }
            st = walk(arch, child, contents, t, total, err);
        } else {
            *total += ent.fileSize;
            uint8_t *data = NULL;
            size_t size = 0;
            if (contents)
                st = read_file(arch, child, &data, &size, err);
            if (st == RS_OK && !rs_tree_add(t, child, data, size))
                st = rs_fail(err, RS_ERR_NOMEM, RS_TR(NOMEM));
            free(data);
        }
        if (st != RS_OK)
            break;
    }
    FSDIR_Close(dh);
    return st;
}

static rs_status save_read(void *ctx, const rs_entry *entry, rs_buf *out, bool *exists, rs_error *err)
{
    (void)entry;
    ctr_title *t = ctx;
    *exists = false;
    if (!t->has_save)
        return RS_OK;
    FS_Archive arch;
    Result rc = open_save(t, &arch);
    if (R_FAILED(rc))
        return rs_fail(err, RS_ERR_IO, RS_TR(CTR_SAVE_READ), (unsigned long)rc);
    rs_tree tree = {0};
    u64 total = 0;
    rs_status st = walk(arch, "", true, &tree, &total, err);
    FSUSER_CloseArchive(arch);
    if (st == RS_OK)
        st = rs_tree_archive(&tree, out, err);
    rs_tree_free(&tree);
    *exists = st == RS_OK;
    return st;
}

/* Empties the root of the archive (the root itself stays). */
static Result clear_root(FS_Archive arch)
{
    rs_tree top = {0};
    ctr_path p;
    Handle dh;
    Result rc = FSUSER_OpenDirectory(&dh, arch, make_path(&p, ""));
    if (R_FAILED(rc))
        return rc;
    for (;;) {
        FS_DirectoryEntry ent;
        u32 n = 0;
        rc = FSDIR_Read(dh, &n, 1, &ent);
        if (R_FAILED(rc) || n == 0)
            break;
        char name[RS_PATH_MAX], child[RS_PATH_MAX];
        utf16_to_string(ent.name, name, sizeof name);
        bool dir = ent.attributes & FS_ATTRIBUTE_DIRECTORY;
        snprintf(child, sizeof child, "%s%s", name, dir ? "/" : "");
        if (!rs_tree_add(&top, child, NULL, 0)) {
            rc = -1;
            break;
        }
    }
    FSDIR_Close(dh);
    for (int i = 0; R_SUCCEEDED(rc) && i < top.count; i++) {
        const char *path = top.items[i].path;
        bool dir = path[strlen(path) - 1] == '/';
        rc = dir ? FSUSER_DeleteDirectoryRecursively(arch, make_path(&p, path))
                 : FSUSER_DeleteFile(arch, make_path(&p, path));
    }
    rs_tree_free(&top);
    return rc;
}

static Result write_entry(FS_Archive arch, const rs_tree_entry *e)
{
    ctr_path p;
    size_t len = strlen(e->path);
    if (e->path[len - 1] == '/')
        return FSUSER_CreateDirectory(arch, make_path(&p, e->path), 0);
    /* Created at its size, then written (fsstream.cpp). */
    FS_Path path = make_path(&p, e->path);
    Result rc = FSUSER_CreateFile(arch, path, 0, e->size);
    Handle fh = 0;
    if (R_SUCCEEDED(rc))
        rc = FSUSER_OpenFile(&fh, arch, path, FS_OPEN_WRITE, 0);
    if (R_SUCCEEDED(rc) && e->size) {
        u32 written = 0;
        rc = FSFILE_Write(fh, &written, 0, e->data, (u32)e->size, FS_WRITE_FLUSH);
        if (R_SUCCEEDED(rc) && written != e->size)
            rc = -1;
    }
    if (fh)
        FSFILE_Close(fh);
    return rc;
}

static rs_status save_write(void *ctx, const rs_entry *entry, const uint8_t *tar, size_t len, rs_error *err)
{
    (void)entry;
    ctr_title *t = ctx;
    /* The system cannot create the archive in the game's place: its size
     * and number of files are the game's own. */
    if (!t->has_save)
        return rs_fail(err, RS_ERR_REFUSED, RS_TR(CTR_NO_SAVE));
    rs_tree want = {0}, current = {0};
    rs_status st = rs_tree_parse(tar, len, &want, err);
    if (st != RS_OK)
        return st;
    u64 needed = 0;
    for (int i = 0; i < want.count; i++)
        needed += want.items[i].size;

    FS_Archive arch;
    Result rc = open_save(t, &arch);
    if (R_FAILED(rc)) {
        rs_tree_free(&want);
        return rs_fail(err, RS_ERR_IO, RS_TR(CTR_SAVE_WRITE), (unsigned long)rc);
    }
    /* Room for the new files: the free space plus what the current files
     * take, checked before anything is removed. */
    u64 free_bytes = 0, used = 0;
    st = walk(arch, "", false, &current, &used, err);
    rs_tree_free(&current);
    if (st == RS_OK && R_SUCCEEDED(FSUSER_GetFreeBytes(&free_bytes, arch)) && needed > free_bytes + used)
        st = rs_fail(err, RS_ERR_REFUSED, RS_TR(CTR_SAVE_TOO_BIG), (unsigned long)(needed / 1024),
                     (unsigned long)((free_bytes + used) / 1024));

    if (st == RS_OK) {
        rc = clear_root(arch);
        for (int i = 0; R_SUCCEEDED(rc) && i < want.count; i++)
            rc = write_entry(arch, &want.items[i]);
        /* Nothing is applied before the commit when the game's save keeps
         * a duplicate of its data. */
        if (R_SUCCEEDED(rc))
            rc = FSUSER_ControlArchive(arch, ARCHIVE_ACTION_COMMIT_SAVE_DATA, NULL, 0, NULL, 0);
        if (R_FAILED(rc))
            st = rs_fail(err, RS_ERR_IO, RS_TR(CTR_SAVE_WRITE), (unsigned long)rc);
    }
    FSUSER_CloseArchive(arch);
    rs_tree_free(&want);
    if (st != RS_OK)
        return st;

    /* Without this, some games refuse a save that was restored (io.cpp). */
    u64 secure = ((u64)SECUREVALUE_SLOT_SD << 32) | (((u64)(u32)t->id >> 8) << 8);
    u8 out = 0;
    rc = FSUSER_ControlSecureSave(SECURESAVE_ACTION_DELETE, &secure, sizeof secure, &out, 1);
    if (R_FAILED(rc))
        return rs_fail(err, RS_ERR_IO, RS_TR(CTR_SECURE_VALUE), (unsigned long)rc);
    return RS_OK;
}

/* ---- Titles ------------------------------------------------------------ */

/* The SMDH of a title (its icon file): an 8-byte header ("SMDH"), then 16
 * titles of 0x200 bytes, the second one English, each starting with a
 * 0x80-byte short title; the settings and the icons follow. */
#define SMDH_SIZE 0x36C0
#define SMDH_ENGLISH_SHORT (8 + 0x200)

/* The English short title of the game's icon, read from the "icon" file of
 * its ExeFS. The whole file is read from its start, as Checkpoint and FBI
 * do: reading the title alone, at its offset, failed on a 2DS. */
static bool read_icon_title(const ctr_title *t, char *out, size_t size)
{
    const u32 arch_path[4] = {(u32)t->id, (u32)(t->id >> 32), t->media, 0};
    static const u32 file_path[5] = {0, 0, 2, 0x6E6F6369 /* "icon" */, 0};
    Handle fh;
    Result rc = FSUSER_OpenFileDirectly(&fh, ARCHIVE_SAVEDATA_AND_CONTENT,
                                        (FS_Path){PATH_BINARY, sizeof arch_path, arch_path},
                                        (FS_Path){PATH_BINARY, sizeof file_path, file_path}, FS_OPEN_READ, 0);
    if (R_FAILED(rc))
        return false;
    u8 *smdh = calloc(1, SMDH_SIZE);
    u32 got = 0;
    rc = smdh ? FSFILE_Read(fh, &got, 0, smdh, SMDH_SIZE) : -1;
    FSFILE_Close(fh);
    if (R_FAILED(rc) || got < SMDH_ENGLISH_SHORT + 0x80 || memcmp(smdh, "SMDH", 4) != 0) {
        free(smdh);
        return false;
    }
    uint16_t name[0x41] = {0};
    memcpy(name, smdh + SMDH_ENGLISH_SHORT, 0x80);
    free(smdh);
    utf16_to_string(name, out, size);
    /* Only characters the console's font can show. */
    const char *s = out;
    while (*s) {
        unsigned c = rs_utf8_next(&s);
        if (c == '\n')
            continue;
        if (c < 0x20 || !rs_cp437(c))
            return false;
    }
    for (char *c = out; *c; c++)
        if (*c == '\n')
            *c = ' ';
    return out[0] != 0;
}

static void add_title(ctr_titles *list, u64 id, FS_MediaType media)
{
    if ((u32)(id >> 32) != GAME_HIGH)
        return;
    for (int i = 0; i < list->count; i++)
        if (list->items[i].id == id)
            return; /* installed and in the cartridge slot: the installed one */
    /* Only the titles whose save archive opens, as Checkpoint: this leaves
     * out the homebrews installed as CIA (ftpd, RetroArch...), which share
     * the games' title IDs, and the games never started, to which nothing
     * can be downloaded anyway. */
    ctr_title probe = {.id = id, .media = media};
    FS_Archive arch;
    if (R_FAILED(open_save(&probe, &arch)))
        return;
    FSUSER_CloseArchive(arch);
    ctr_title *grown = realloc(list->items, (size_t)(list->count + 1) * sizeof *grown);
    if (!grown)
        return;
    list->items = grown;
    ctr_title *t = &list->items[list->count++];
    *t = probe;
    t->has_save = true;
    if (!read_icon_title(t, t->name, sizeof t->name)) {
        char code[16] = {0};
        if (R_SUCCEEDED(AM_GetTitleProductCode(media, id, code)) && code[0])
            rs_strlcpy(t->name, code, sizeof t->name);
        else
            snprintf(t->name, sizeof t->name, "%016llX", (unsigned long long)id);
    }
}

static Result add_media(ctr_titles *list, FS_MediaType media)
{
    u32 count = 0;
    Result rc = AM_GetTitleCount(media, &count);
    if (R_FAILED(rc) || count == 0)
        return rc;
    u64 *ids = malloc(count * sizeof *ids);
    if (!ids)
        return -1;
    u32 read = 0;
    rc = AM_GetTitleList(&read, media, count, ids);
    for (u32 i = 0; R_SUCCEEDED(rc) && i < read; i++)
        add_title(list, ids[i], media);
    free(ids);
    return rc;
}

static int by_name(const void *a, const void *b)
{
    return strcasecmp(((const ctr_title *)a)->name, ((const ctr_title *)b)->name);
}

void titles_list(ctr_titles *out)
{
    memset(out, 0, sizeof *out);
    Result rc = amInit();
    if (R_SUCCEEDED(rc))
        rc = add_media(out, MEDIATYPE_SD);
    if (R_SUCCEEDED(rc)) {
        bool inserted = false;
        FS_CardType type;
        if (R_SUCCEEDED(FSUSER_CardSlotIsInserted(&inserted)) && inserted &&
            R_SUCCEEDED(FSUSER_GetCardType(&type)) && type == CARD_CTR)
            add_media(out, MEDIATYPE_GAME_CARD);
        amExit();
    }
    if (R_FAILED(rc))
        snprintf(out->error, sizeof out->error, RS_TR(CTR_LIST_FAILED), (unsigned long)rc);
    if (out->count > 1)
        qsort(out->items, (size_t)out->count, sizeof *out->items, by_name);
    for (int i = 0; i < out->count; i++)
        out->items[i].io = (rs_save_io){.read = save_read, .write = save_write, .ctx = &out->items[i]};
}

void titles_free(ctr_titles *t)
{
    free(t->items);
    memset(t, 0, sizeof *t);
}

void titles_add_to_library(ctr_titles *t, const rs_profile *tree, const char *backup_root, rs_library *lib)
{
    if (t->count == 0)
        return;
    rs_game *grown = realloc(lib->games, (size_t)(lib->count + t->count) * sizeof *grown);
    if (!grown)
        return;
    lib->games = grown;
    for (int i = 0; i < t->count; i++) {
        const ctr_title *ti = &t->items[i];
        rs_game *g = &lib->games[lib->count++];
        memset(g, 0, sizeof *g);
        rs_entry *e = &g->entry;
        unsigned long long id = (unsigned long long)ti->id;
        /* Keys of the save's state and queue; never real files. */
        snprintf(e->rom_path, sizeof e->rom_path, "3ds/%016llX", id);
        snprintf(e->save_path, sizeof e->save_path, "3ds/%016llX", id);
        snprintf(e->game_id, sizeof e->game_id, "3ds:%016llX", id);
        rs_strlcpy(g->detected_id, e->game_id, sizeof g->detected_id);
        rs_strlcpy(e->title, ti->name, sizeof e->title);
        rs_strlcpy(e->emulator, "3ds", sizeof e->emulator);
        rs_strlcpy(e->backup_dir, backup_root, sizeof e->backup_dir);
        e->io = &ti->io;
        e->profile = tree;
        if (!tree)
            rs_strlcpy(e->unavailable, RS_TR(CTR_NO_TREE_PROFILE), sizeof e->unavailable);
    }
}

ctr_title *titles_of_entry(const rs_entry *entry)
{
    return entry->io ? entry->io->ctx : NULL;
}

bool titles_launch(const ctr_title *t, char *why, size_t size)
{
    Result rc = APT_PrepareToDoApplicationJump(0, t->id, t->media);
    if (R_SUCCEEDED(rc)) {
        u8 param[0x300] = {0};
        u8 hmac[0x20] = {0};
        rc = APT_DoApplicationJump(param, sizeof param, hmac);
    }
    if (R_FAILED(rc)) {
        snprintf(why, size, RS_TR(CTR_LAUNCH_FAILED), (unsigned long)rc);
        return false;
    }
    return true;
}
