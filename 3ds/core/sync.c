/*
 * sync.c - sync engine, statuses and .backup copies (see sync.h).
 *
 * Each function mirrors the method of the same name in romsync_core's
 * engine.dart; the tests in tests/test_sync.c are the same as its
 * sync_test.dart.
 */
#include "sync.h"

#include <dirent.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "sha.h"

static void emit(const rs_engine *e, rs_event_kind kind, const char *game_id, const char *message)
{
    if (e->on_event)
        e->on_event(e->event_ctx, kind, game_id, message);
}

rs_time rs_engine_now(const rs_engine *e)
{
    return rs_clock_correct(&e->states->clock, e->now(e->now_ctx));
}

/* ---- Local saves ------------------------------------------------------- */

rs_status rs_read_local_save(const rs_entry *entry, rs_local_save *out, rs_error *err)
{
    memset(out, 0, sizeof *out);
    /* On the 3DS no emulator runs while RomSync does, so the file cannot
     * change during the read (the PC client needs a stable-read loop). */
    rs_buf file = {0};
    rs_status st = rs_read_file(entry->save_path, &file, err);
    if (st == RS_ERR_NOT_FOUND)
        return RS_OK;
    if (st == RS_OK)
        st = rs_profile_decode(entry->profile, file.data, file.len, &out->raw, err);
    rs_buf_free(&file);
    if (st != RS_OK)
        return st;
    out->exists = true;
    rs_sha256_hex(out->raw.data, out->raw.len, out->hash);
    return RS_OK;
}

void rs_local_save_free(rs_local_save *s)
{
    rs_buf_free(&s->raw);
    s->exists = false;
}

/* ---- Upload queue ------------------------------------------------------ */

rs_status rs_engine_flush(rs_engine *e, rs_flush_result *res, rs_error *err)
{
    memset(res, 0, sizeof *res);
    int i = 0;
    while (i < e->queue->count) {
        rs_upload u = e->queue->items[i]; /* a copy: removing shifts the array */
        rs_buf data = {0};
        rs_status st = rs_queue_content(e->queue, &u, &data, err);
        if (st != RS_OK)
            return st;
        const rs_save_state *s = rs_state_for(e->states, u.save_path, u.game_id);
        int64_t base = s ? s->version_id : 0;

        rs_upload_result r;
        rs_error up_err = {0};
        st = rs_api_upload(e->api, u.game_id, data.data, data.len, u.saved_at, u.upload_id, base, u.emulator,
                           u.title, &r, &up_err);
        if (st == RS_OK) {
            rs_buf_free(&data);
            /* The local hash is kept: the server may have cut padding, so
             * its hash can differ from the local file's. */
            st = rs_state_record(e->states, u.save_path, u.game_id, r.version.id, u.sha256, rs_engine_now(e), err);
            if (st == RS_OK)
                st = rs_queue_remove(e->queue, u.upload_id, err);
            if (st != RS_OK)
                return st;
            res->sent++;
            emit(e, RS_EVENT_UPLOADED, u.game_id,
                 !r.created  ? "Save identique à la version active"
                 : r.active  ? (r.conflict ? "Save envoyée (divergence : la plus récente gagne)" : "Save envoyée")
                             : "Save envoyée, mais une version plus récente reste active");
            continue;
        }
        if (st == RS_ERR_OFFLINE || (st == RS_ERR_API && (up_err.http_status >= 500 || up_err.http_status == 429))) {
            rs_buf_free(&data);
            res->offline = true;
            char msg[96];
            snprintf(msg, sizeof msg, "Serveur injoignable : %d envoi(s) en attente", e->queue->count);
            emit(e, RS_EVENT_OFFLINE, u.game_id, msg);
            break;
        }
        if (st == RS_ERR_API && up_err.http_status == 401) {
            rs_buf_free(&data);
            res->unauthorized = true;
            emit(e, RS_EVENT_FAILED, u.game_id, "Appareil non autorisé : appaire-le à nouveau");
            break;
        }
        if (st != RS_ERR_API) {
            rs_buf_free(&data);
            if (err)
                *err = up_err;
            return st;
        }
        /* Refused for good (size mismatch...): keep the content aside in
         * <queue>/failed/<upload id>.bin and drop it from the queue. */
        char name[64], failed_dir[RS_PATH_MAX], failed[RS_PATH_MAX];
        rs_path_join(failed_dir, sizeof failed_dir, e->queue->dir, "failed");
        snprintf(name, sizeof name, "%s.bin", u.upload_id);
        rs_path_join(failed, sizeof failed, failed_dir, name);
        st = rs_write_file_atomic(failed, data.data, data.len, err);
        rs_buf_free(&data);
        if (st == RS_OK)
            st = rs_queue_remove(e->queue, u.upload_id, err);
        if (st != RS_OK)
            return st;
        res->failures++;
        snprintf(res->failure_message, sizeof res->failure_message,
                 "Envoi refusé (%s) : %s. Copie conservée : %s", up_err.code, up_err.message, failed);
        emit(e, RS_EVENT_FAILED, u.game_id, res->failure_message);
    }
    return RS_OK;
}

rs_status rs_engine_enqueue(rs_engine *e, const rs_entry *entry, const rs_local_save *save, bool *queued,
                            rs_error *err)
{
    if (queued)
        *queued = false;
    if (rs_queue_has(e->queue, entry->save_path, entry->game_id, save->hash))
        return RS_OK;
    rs_time now = rs_engine_now(e);
    rs_status st = rs_queue_add(e->queue, entry->game_id, entry->save_path, save->raw.data, save->raw.len,
                                save->hash, now, entry->emulator, entry->title, now, NULL, err);
    if (st != RS_OK)
        return st;
    if (queued)
        *queued = true;
    emit(e, RS_EVENT_QUEUED, entry->game_id, "Save mise en file d'attente");
    return RS_OK;
}

/* ---- Before launch ----------------------------------------------------- */

/* The server cannot be reached: queue local changes and report it. */
static rs_status go_offline(rs_engine *e, const rs_entry *entry, const rs_local_save *local,
                            rs_prepare_result *out, rs_error *err)
{
    const rs_save_state *s = rs_state_for(e->states, entry->save_path, entry->game_id);
    if (local->exists && (!s || strcmp(local->hash, s->hash) != 0)) {
        rs_status st = rs_engine_enqueue(e, entry, local, NULL, err);
        if (st != RS_OK)
            return st;
    }
    out->offline = true;
    rs_strlcpy(out->message, "Serveur injoignable : les envois partiront dès que le serveur répondra.",
               sizeof out->message);
    return RS_OK;
}

/* Replaces the local save with version, after a copy into .backup. */
static rs_status download(rs_engine *e, const rs_entry *entry, const rs_version *v, size_t chip_size,
                          rs_prepare_result *out, rs_error *err)
{
    rs_buf raw = {0}, file = {0};
    rs_status st = rs_api_download(e->api, v->id, &raw, err);
    if (st == RS_OK)
        st = rs_backup(entry->save_path, rs_engine_now(e), e->keep_backups, out->backup_path,
                       sizeof out->backup_path, err);
    if (st == RS_OK)
        st = rs_profile_encode(entry->profile, raw.data, raw.len, chip_size, &file, err);
    if (st == RS_OK)
        st = rs_write_file_atomic(entry->save_path, file.data, file.len, err);
    if (st == RS_OK) {
        char hash[65];
        rs_sha256_hex(raw.data, raw.len, hash);
        st = rs_state_record(e->states, entry->save_path, entry->game_id, v->id, hash, rs_engine_now(e), err);
    }
    rs_buf_free(&raw);
    rs_buf_free(&file);
    if (st == RS_OK) {
        out->downloaded = true;
        emit(e, RS_EVENT_DOWNLOADED, entry->game_id, "Save du serveur téléchargée");
    }
    return st;
}

rs_status rs_engine_prepare(rs_engine *e, const rs_entry *entry, size_t chip_size, rs_prepare_result *out,
                            rs_error *err)
{
    memset(out, 0, sizeof *out);
    if (entry->unavailable[0])
        return rs_fail(err, RS_ERR_REFUSED, "%s", entry->unavailable);
    if (entry->needs_choice)
        return rs_fail(err, RS_ERR_REFUSED,
                       "Plusieurs ROMs partagent l'identifiant %s : choisis d'abord de partager ou séparer "
                       "leur save.",
                       entry->game_id);

    /* 1. Empty the queue if the server answers. */
    rs_flush_result flush;
    rs_status st = rs_engine_flush(e, &flush, err);
    if (st != RS_OK)
        return st;
    if (flush.unauthorized)
        return rs_fail(err, RS_ERR_REFUSED, "Appareil non autorisé : appaire-le à nouveau.");

    rs_local_save local;
    st = rs_read_local_save(entry, &local, err);
    if (st != RS_OK)
        return st;
    if (flush.offline) {
        st = go_offline(e, entry, &local, out, err);
        goto done;
    }

    /* 2. Active version of the game. */
    rs_version active;
    bool has_active;
    st = rs_api_active(e->api, entry->game_id, &active, &has_active, err);
    if (st == RS_ERR_OFFLINE) {
        st = go_offline(e, entry, &local, out, err);
        goto done;
    }
    if (st != RS_OK)
        goto done;

    const rs_save_state *s = rs_state_for(e->states, entry->save_path, entry->game_id);
    bool local_changed = local.exists && (!s || strcmp(local.hash, s->hash) != 0);
    if (local_changed) {
        if (has_active && strcmp(local.hash, active.sha256) == 0) {
            /* Same content as the server: nothing to send. */
            st = rs_state_record(e->states, entry->save_path, entry->game_id, active.id, local.hash,
                                 rs_engine_now(e), err);
            if (st != RS_OK)
                goto done;
        } else {
            /* 4. Changed outside a sync (game played since the last start):
             * send it first; the server applies "most recent wins" before
             * the download. */
            st = rs_engine_enqueue(e, entry, &local, NULL, err);
            if (st == RS_OK)
                st = rs_engine_flush(e, &flush, err);
            if (st != RS_OK)
                goto done;
            if (flush.offline) {
                st = go_offline(e, entry, &local, out, err);
                goto done;
            }
            if (flush.failures) {
                st = rs_fail(err, RS_ERR_REFUSED, "%s", flush.failure_message);
                goto done;
            }
            out->uploaded = true;
            st = rs_api_active(e->api, entry->game_id, &active, &has_active, err);
            if (st == RS_ERR_OFFLINE) {
                st = go_offline(e, entry, &local, out, err);
                goto done;
            }
            if (st != RS_OK)
                goto done;
        }
        s = rs_state_for(e->states, entry->save_path, entry->game_id);
    }

    /* 3. Unchanged local save and a newer version on the server: download. */
    if (has_active && (!s || active.id != s->version_id)) {
        st = download(e, entry, &active, chip_size, out, err);
        if (st == RS_ERR_OFFLINE)
            st = go_offline(e, entry, &local, out, err);
        goto done;
    }
    emit(e, RS_EVENT_UP_TO_DATE, entry->game_id, "Save à jour");

done:
    rs_local_save_free(&local);
    return st;
}

rs_status rs_engine_offline_pass(rs_engine *e, const rs_entry *entry, rs_prepare_result *out, rs_error *err)
{
    memset(out, 0, sizeof *out);
    if (entry->unavailable[0] || entry->needs_choice)
        return rs_fail(err, RS_ERR_REFUSED, "%s",
                       entry->unavailable[0] ? entry->unavailable : "Choix requis avant la synchronisation.");
    rs_local_save local;
    rs_status st = rs_read_local_save(entry, &local, err);
    if (st == RS_OK)
        st = go_offline(e, entry, &local, out, err);
    rs_local_save_free(&local);
    return st;
}

/* ---- Status ------------------------------------------------------------ */

rs_save_status rs_compute_status(bool needs_choice, bool unavailable, const char *local_hash,
                                 const rs_save_state *state, const rs_remote_game *remote, int queued,
                                 bool online)
{
    if (needs_choice)
        return RS_STATUS_NEEDS_CHOICE;
    if (unavailable)
        return RS_STATUS_UNAVAILABLE;
    bool local_changed = local_hash && (!state || strcmp(local_hash, state->hash) != 0);
    if (!online)
        return local_changed || queued > 0 ? RS_STATUS_TO_UPLOAD : RS_STATUS_OFFLINE;
    if (local_changed || queued > 0)
        return RS_STATUS_TO_UPLOAD;
    if (!remote || !remote->has_active)
        return local_hash ? RS_STATUS_TO_UPLOAD : RS_STATUS_NO_SAVE;
    if (!local_hash || !state || remote->active.id != state->version_id)
        return RS_STATUS_TO_DOWNLOAD;
    return RS_STATUS_UP_TO_DATE;
}

const char *rs_status_label(rs_save_status s)
{
    switch (s) {
    case RS_STATUS_UP_TO_DATE:
        return "à jour";
    case RS_STATUS_TO_UPLOAD:
        return "à envoyer";
    case RS_STATUS_TO_DOWNLOAD:
        return "à télécharger";
    case RS_STATUS_OFFLINE:
        return "hors ligne";
    case RS_STATUS_NEEDS_CHOICE:
        return "choix requis";
    case RS_STATUS_UNAVAILABLE:
        return "indisponible";
    case RS_STATUS_NO_SAVE:
        return "pas de save";
    }
    return "?";
}

/* ---- .backup copies ---------------------------------------------------- */

static void backup_dir(const char *save_path, char *out, size_t size)
{
    char dir[RS_PATH_MAX];
    rs_dirname(save_path, dir, sizeof dir);
    rs_path_join(out, size, dir, ".backup");
}

static int compare_desc(const void *a, const void *b)
{
    return strcmp(*(char *const *)b, *(char *const *)a);
}

/* Lists the copies of save_path, newest first (the date in the name sorts
 * chronologically). Returns the number of names; free them with free(). */
static int list_backups(const char *save_path, char ***names)
{
    char dir[RS_PATH_MAX], prefix[RS_PATH_MAX];
    backup_dir(save_path, dir, sizeof dir);
    snprintf(prefix, sizeof prefix, "%s.", rs_basename(save_path));
    *names = NULL;
    DIR *d = opendir(dir);
    if (!d)
        return 0;
    int n = 0, cap = 0;
    struct dirent *ent;
    while ((ent = readdir(d)) != NULL) {
        if (strncmp(ent->d_name, prefix, strlen(prefix)) != 0)
            continue;
        if (n == cap) {
            cap = cap ? cap * 2 : 16;
            char **grown = realloc(*names, (size_t)cap * sizeof *grown);
            if (!grown)
                break;
            *names = grown;
        }
        (*names)[n++] = rs_strdup(ent->d_name);
    }
    closedir(d);
    if (n > 1)
        qsort(*names, (size_t)n, sizeof **names, compare_desc);
    return n;
}

static void free_names(char **names, int n)
{
    for (int i = 0; i < n; i++)
        free(names[i]);
    free(names);
}

rs_status rs_backup(const char *save_path, rs_time now, int keep, char *copy, size_t copy_size, rs_error *err)
{
    if (copy_size)
        copy[0] = 0;
    if (!rs_file_exists(save_path))
        return RS_OK;
    char dir[RS_PATH_MAX], stamp[32], name[RS_PATH_MAX], path[RS_PATH_MAX];
    backup_dir(save_path, dir, sizeof dir);
    /* "2026-11-07T12-00-00Z": ':' is not allowed in FAT file names. */
    rs_time_format_iso(now, stamp, sizeof stamp);
    for (char *c = stamp; *c; c++)
        if (*c == ':')
            *c = '-';
    snprintf(name, sizeof name, "%s.%s", rs_basename(save_path), stamp);
    rs_path_join(path, sizeof path, dir, name);
    rs_status st = rs_copy_file(save_path, path, err);
    if (st != RS_OK)
        return st;
    if (copy_size)
        rs_strlcpy(copy, path, copy_size);

    char **names;
    int n = list_backups(save_path, &names);
    for (int i = keep < 0 ? 0 : keep; i < n; i++) {
        rs_path_join(path, sizeof path, dir, names[i]);
        remove(path);
    }
    free_names(names, n);
    return RS_OK;
}

int rs_backup_count(const char *save_path, char *newest, size_t newest_size)
{
    char **names;
    int n = list_backups(save_path, &names);
    if (newest && newest_size) {
        newest[0] = 0;
        if (n > 0) {
            char dir[RS_PATH_MAX];
            backup_dir(save_path, dir, sizeof dir);
            rs_path_join(newest, newest_size, dir, names[0]);
        }
    }
    free_names(names, n);
    return n;
}

/* ---- Changing the save file of a game ---------------------------------- */

bool rs_is_stale_save(const rs_entry *entry, const rs_state_store *states)
{
    if (entry->unavailable[0] || !rs_file_exists(entry->save_path))
        return false;
    const rs_save_state *s = rs_state_get(states, entry->save_path);
    return !s || strcmp(s->game_id, entry->game_id) != 0;
}

rs_status rs_set_aside(const char *save_path, rs_time now, int keep, char *copy, size_t copy_size,
                       rs_error *err)
{
    rs_status st = rs_backup(save_path, now, keep, copy, copy_size, err);
    if (st == RS_OK && copy_size && copy[0] && remove(save_path) != 0)
        st = rs_fail(err, RS_ERR_IO, "Impossible de déplacer %s", save_path);
    return st;
}
