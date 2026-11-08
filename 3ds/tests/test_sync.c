/*
 * test_sync.c - the sync engine against the fake server: the cases of
 * romsync_core's sync_test.dart, plus the 3DS-specific ones (clock
 * correction, save slot change).
 *
 * One difference with the PC client: X-Saved-At is the corrected time at
 * which RomSync first sees a new save content, not the file's date (which
 * nds-bootstrap does not update). The cases that relied on file dates are
 * written with that rule.
 */
#include <stdlib.h>
#include <string.h>

#include "../core/sha.h"
#include "../core/sync.h"
#include "fake_server.h"
#include "suites.h"
#include "test.h"

#define HOUR 3600
#define MINUTE 60

typedef struct {
    char dir[RS_PATH_MAX];
    char save_path[RS_PATH_MAX];
    fake_server server;
    rs_profile raw;
    rs_state_store states;
    rs_queue queue;
    rs_api api;
    rs_engine engine;
    rs_time now; /* console clock */
    int keep;
    rs_event_kind last_event;
} harness;

static rs_time h_now(void *ctx)
{
    return ((harness *)ctx)->now;
}

static void h_event(void *ctx, rs_event_kind kind, const char *game_id, const char *message)
{
    (void)game_id;
    (void)message;
    ((harness *)ctx)->last_event = kind;
}

/* (Re)opens the state and the queue from disk, like a restart. */
static void h_open(harness *h)
{
    char path[RS_PATH_MAX];
    rs_state_close(&h->states);
    rs_queue_close(&h->queue);
    rs_path_join(path, sizeof path, h->dir, "state.json");
    CHECK_INT(rs_state_open(&h->states, path, NULL), RS_OK);
    rs_path_join(path, sizeof path, h->dir, "queue");
    CHECK_INT(rs_queue_open(&h->queue, path, NULL), RS_OK);
    h->api = (rs_api){.send = fake_send, .send_ctx = &h->server, .clock = &h->states.clock, .now = h_now,
                      .now_ctx = h};
    rs_strlcpy(h->api.base_url, "http://fake", sizeof h->api.base_url);
    rs_strlcpy(h->api.token, "t", sizeof h->api.token);
    h->engine = (rs_engine){.api = &h->api, .states = &h->states, .queue = &h->queue, .keep_backups = h->keep,
                            .now = h_now, .now_ctx = h, .on_event = h_event, .event_ctx = h};
}

static harness *h_new(void)
{
    harness *h = calloc(1, sizeof *h);
    rs_strlcpy(h->dir, t_tmpdir(), sizeof h->dir);
    snprintf(h->save_path, sizeof h->save_path, "%s/roms/saves/Game.sav", h->dir);
    fake_init(&h->server);
    CHECK_INT(rs_profile_parse("{\"id\":\"twilight\",\"name\":\"TWiLight\",\"status\":\"to_verify\","
                               "\"extension\":\".sav\",\"header\":null,\"footer\":null,"
                               "\"size\":{\"output\":\"exact\"}}",
                               &h->raw, NULL),
              RS_OK);
    h->now = 1794052800; /* 2026-11-07T12:00:00Z */
    h->keep = 10;
    h_open(h);
    return h;
}

static void h_free(harness *h)
{
    rs_state_close(&h->states);
    rs_queue_close(&h->queue);
    rs_profile_free(&h->raw);
    fake_free(&h->server);
    t_rmtree(h->dir);
    free(h);
}

static rs_entry h_entry(harness *h, const char *game_id)
{
    rs_entry e = {0};
    snprintf(e.rom_path, sizeof e.rom_path, "%s/roms/Game.nds", h->dir);
    rs_strlcpy(e.title, "GAME", sizeof e.title);
    rs_strlcpy(e.game_id, game_id, sizeof e.game_id);
    rs_strlcpy(e.save_path, h->save_path, sizeof e.save_path);
    e.profile = &h->raw;
    rs_strlcpy(e.emulator, "twilight", sizeof e.emulator);
    return e;
}

/* A 512-byte save whose content depends on seed. */
static const uint8_t *save(int seed)
{
    static uint8_t b[8][512];
    static int next = 0;
    uint8_t *out = b[next++ % 8];
    for (int i = 0; i < 512; i++)
        out[i] = (uint8_t)((i + seed * 7) & 0xFF);
    return out;
}

static void write_local(harness *h, const uint8_t *data)
{
    t_write(h->save_path, data, 512);
}

static bool local_is(harness *h, const uint8_t *data)
{
    rs_buf b = {0};
    bool same = rs_read_file(h->save_path, &b, NULL) == RS_OK && b.len == 512 && memcmp(b.data, data, 512) == 0;
    rs_buf_free(&b);
    return same;
}

static bool file_is(const char *path, const uint8_t *data)
{
    rs_buf b = {0};
    bool same = rs_read_file(path, &b, NULL) == RS_OK && b.len == 512 && memcmp(b.data, data, 512) == 0;
    rs_buf_free(&b);
    return same;
}

static bool active_is(harness *h, const char *code, const uint8_t *data)
{
    const fake_version *v = fake_active(&h->server, code);
    return v && v->data.len == 512 && memcmp(v->data.data, data, 512) == 0;
}

static rs_prepare_result prepare_choice(harness *h, const char *game_id, rs_choice choice, rs_status expected)
{
    rs_entry e = h_entry(h, game_id);
    rs_prepare_result r;
    rs_error err = {0};
    rs_status st = rs_engine_prepare(&h->engine, &e, 0, choice, &r, &err);
    CHECK_INT(st, expected);
    if (st != expected)
        fprintf(stderr, "    %s\n", err.message);
    return r;
}

static rs_prepare_result prepare(harness *h, const char *game_id, rs_status expected)
{
    return prepare_choice(h, game_id, RS_CHOICE_NONE, expected);
}

/* Whether a version of the fake server holds data (512 bytes). */
static const fake_version *version_with(harness *h, const uint8_t *data)
{
    char sha[65];
    rs_sha256_hex(data, 512, sha);
    for (int i = 0; i < h->server.version_count; i++)
        if (strcmp(h->server.versions[i].sha, sha) == 0)
            return &h->server.versions[i];
    return NULL;
}

/* ---- prepare (at startup) ---------------------------------------------- */

static void first_save_of_an_unknown_game_is_uploaded(void)
{
    harness *h = h_new();
    write_local(h, save(1));
    rs_prepare_result r = prepare(h, "IRBF", RS_OK);
    CHECK(!r.offline && r.uploaded && !r.downloaded);
    CHECK(active_is(h, "IRBF", save(1)));
    const rs_save_state *s = rs_state_get(&h->states, h->save_path);
    CHECK(s && s->version_id == fake_active(&h->server, "IRBF")->id);
    char sha[65];
    rs_sha256_hex(save(1), 512, sha);
    CHECK(s && strcmp(s->hash, sha) == 0);
    CHECK_INT(h->queue.count, 0);
    h_free(h);
}

static void unchanged_local_and_newer_server_version_downloads_with_backup(void)
{
    harness *h = h_new();
    write_local(h, save(1));
    prepare(h, "IRBF", RS_OK);
    fake_add_version(&h->server, "IRBF", save(2), 512, h->now - 10 * MINUTE); /* another device */
    h->now += MINUTE;
    rs_prepare_result r = prepare(h, "IRBF", RS_OK);
    CHECK(r.downloaded && !r.uploaded);
    CHECK(local_is(h, save(2)));
    CHECK(file_is(r.backup_path, save(1)));
    char dir[RS_PATH_MAX], expected[RS_PATH_MAX];
    rs_dirname(r.backup_path, dir, sizeof dir);
    snprintf(expected, sizeof expected, "%s/roms/saves/.backup", h->dir);
    CHECK_STR(dir, expected);
    CHECK_INT(rs_state_get(&h->states, h->save_path)->version_id, fake_active(&h->server, "IRBF")->id);
    h_free(h);
}

static void no_local_save_downloads_the_server_version(void)
{
    harness *h = h_new();
    fake_add_version(&h->server, "IRBF", save(5), 512, h->now);
    rs_prepare_result r = prepare(h, "IRBF", RS_OK);
    CHECK(r.downloaded);
    CHECK_STR(r.backup_path, "");
    CHECK(local_is(h, save(5))); /* the saves/ folder is created */
    h_free(h);
}

static void local_save_identical_to_the_server_means_no_transfer(void)
{
    harness *h = h_new();
    const fake_version *v = fake_add_version(&h->server, "IRBF", save(3), 512, h->now);
    write_local(h, save(3));
    rs_prepare_result r = prepare(h, "IRBF", RS_OK);
    CHECK(!r.uploaded && !r.downloaded);
    CHECK_INT(h->server.upload_requests, 0);
    CHECK_INT(rs_state_get(&h->states, h->save_path)->version_id, v->id);
    h_free(h);
}

static void up_to_date_does_nothing(void)
{
    harness *h = h_new();
    write_local(h, save(1));
    prepare(h, "IRBF", RS_OK);
    int before = h->server.upload_requests;
    rs_prepare_result r = prepare(h, "IRBF", RS_OK);
    CHECK(!r.uploaded && !r.downloaded);
    CHECK_INT(h->server.upload_requests, before);
    CHECK_INT(h->last_event, RS_EVENT_UP_TO_DATE);
    h_free(h);
}

static void local_change_with_the_server_unchanged_is_sent_without_question(void)
{
    harness *h = h_new();
    write_local(h, save(1));
    prepare(h, "IRBF", RS_OK);
    h->now += HOUR;
    write_local(h, save(2));
    rs_prepare_result r = prepare(h, "IRBF", RS_OK);
    CHECK(!r.needs_choice && r.uploaded);
    CHECK(active_is(h, "IRBF", save(2)));
    CHECK(!fake_active(&h->server, "IRBF")->conflict);
    h_free(h);
}

static void divergence_sends_and_overwrites_nothing_until_the_user_chooses(void)
{
    harness *h = h_new();
    write_local(h, save(1));
    prepare(h, "IRBF", RS_OK);
    h->now += 3 * HOUR;
    const fake_version *other = fake_add_version(&h->server, "IRBF", save(2), 512, h->now - 2 * HOUR);
    write_local(h, save(3)); /* played here without syncing */
    int requests = h->server.upload_requests;

    rs_prepare_result r = prepare(h, "IRBF", RS_OK);
    CHECK(r.needs_choice);
    CHECK_INT(r.divergence.server.id, other->id);
    CHECK(!r.uploaded && !r.downloaded);
    CHECK_INT(h->server.upload_requests, requests);
    CHECK_INT(h->queue.count, 0);
    CHECK(local_is(h, save(3)));
    /* Asked again next time (no answer). */
    CHECK(prepare(h, "IRBF", RS_OK).needs_choice);
    h_free(h);
}

static void choice_local_is_sent_and_active_even_when_older(void)
{
    harness *h = h_new();
    write_local(h, save(1));
    prepare(h, "IRBF", RS_OK);
    int64_t v1 = fake_active(&h->server, "IRBF")->id;
    h->now += 3 * HOUR;
    fake_add_version(&h->server, "IRBF", save(2), 512, h->now + HOUR); /* other device, dated later */
    write_local(h, save(3));

    rs_prepare_result r = prepare_choice(h, "IRBF", RS_CHOICE_LOCAL, RS_OK);
    CHECK(r.uploaded && !r.downloaded);
    const fake_version *mine = fake_active(&h->server, "IRBF");
    CHECK(active_is(h, "IRBF", save(3)));
    CHECK_INT(mine->base, v1);
    CHECK(mine->conflict);
    CHECK(local_is(h, save(3)));
    CHECK_INT(rs_state_get(&h->states, h->save_path)->version_id, mine->id);
    h_free(h);
}

static void choice_server_archives_the_local_save_then_downloads_with_backup(void)
{
    harness *h = h_new();
    write_local(h, save(1));
    prepare(h, "IRBF", RS_OK);
    h->now += 3 * HOUR;
    const fake_version *other = fake_add_version(&h->server, "IRBF", save(2), 512, h->now - 2 * HOUR);
    int64_t other_id = other->id;
    write_local(h, save(3)); /* seen now: more recent than the other device's */

    rs_prepare_result r = prepare_choice(h, "IRBF", RS_CHOICE_SERVER, RS_OK);
    CHECK(r.uploaded && r.downloaded);
    CHECK_INT(fake_active(&h->server, "IRBF")->id, other_id); /* the archive does not win */
    const fake_version *archived = version_with(h, save(3));
    CHECK(archived && archived->id != other_id);
    CHECK(local_is(h, save(2)));
    CHECK(file_is(r.backup_path, save(3)));
    CHECK_INT(rs_state_get(&h->states, h->save_path)->version_id, other_id);
    CHECK(!prepare(h, "IRBF", RS_OK).needs_choice);
    h_free(h);
}

static void a_choice_against_a_server_too_old_for_x_activate_is_refused(void)
{
    harness *h = h_new();
    write_local(h, save(1));
    prepare(h, "IRBF", RS_OK);
    h->now += 3 * HOUR;
    fake_add_version(&h->server, "IRBF", save(2), 512, h->now - 2 * HOUR);
    write_local(h, save(3));
    h->server.api_level = 0; /* 0.4.0: no GET /server */
    int requests = h->server.upload_requests;
    CHECK(prepare(h, "IRBF", RS_OK).needs_choice);
    rs_entry e = h_entry(h, "IRBF");
    rs_prepare_result r;
    rs_error err = {0};
    CHECK_INT(rs_engine_prepare(&h->engine, &e, 0, RS_CHOICE_SERVER, &r, &err), RS_ERR_REFUSED);
    CHECK(strstr(err.message, "trop ancien") != NULL);
    CHECK_INT(h->server.upload_requests, requests);
    CHECK_INT(h->queue.count, 0);
    CHECK(local_is(h, save(3)));
    h_free(h);
}

static void first_sync_of_a_console_whose_save_differs_from_the_server_is_a_divergence(void)
{
    harness *h = h_new();
    fake_add_version(&h->server, "IRBF", save(2), 512, h->now - 2 * HOUR);
    write_local(h, save(3));
    CHECK(prepare(h, "IRBF", RS_OK).needs_choice);
    CHECK_INT(h->server.upload_requests, 0);
    h_free(h);
}

static void an_upload_right_after_a_download_is_never_divergent(void)
{
    harness *h = h_new();
    fake_add_version(&h->server, "IRBF", save(2), 512, h->now - 2 * HOUR);
    CHECK(prepare(h, "IRBF", RS_OK).downloaded);
    h->now += MINUTE;
    write_local(h, save(3));
    rs_prepare_result r = prepare(h, "IRBF", RS_OK);
    CHECK(!r.needs_choice && r.uploaded);
    CHECK(active_is(h, "IRBF", save(3)));
    CHECK(!fake_active(&h->server, "IRBF")->conflict);
    h_free(h);
}

static void a_save_padded_with_zeros_with_the_active_content_is_no_divergence(void)
{
    harness *h = h_new();
    const fake_version *v = fake_add_version(&h->server, "IRBF", save(2), 512, h->now - 2 * HOUR);
    int64_t id = v->id;
    uint8_t padded[1024];
    memcpy(padded, save(2), 512);
    memset(padded + 512, 0, 512); /* TWiLight Menu++ pads with 0x00 */
    t_write(h->save_path, padded, sizeof padded);
    rs_prepare_result r = prepare(h, "IRBF", RS_OK);
    CHECK(!r.needs_choice && !r.uploaded && !r.downloaded);
    CHECK_INT(h->server.upload_requests, 0);
    CHECK_INT(rs_state_get(&h->states, h->save_path)->version_id, id);
    /* Padded with data instead: a real difference. */
    memset(padded + 512, 7, 512);
    t_write(h->save_path, padded, sizeof padded);
    fake_add_version(&h->server, "IRBF", save(4), 512, h->now);
    CHECK(prepare(h, "IRBF", RS_OK).needs_choice);
    h_free(h);
}

static void a_smaller_save_whose_active_version_only_adds_padding_is_no_divergence(void)
{
    harness *h = h_new();
    uint8_t big[1024];
    memcpy(big, save(2), 512);
    memset(big + 512, 0xFF, 512); /* FRAM 32 KiB seen as 64 KiB */
    const fake_version *v = fake_add_version(&h->server, "IRBF", big, sizeof big, h->now - 2 * HOUR);
    int64_t id = v->id;
    write_local(h, save(2));
    rs_prepare_result r = prepare(h, "IRBF", RS_OK);
    CHECK(!r.needs_choice && !r.uploaded && !r.downloaded);
    CHECK_INT(rs_state_get(&h->states, h->save_path)->version_id, id);
    h_free(h);
}

/* PC version: an automatic upload in the background. On the 3DS: a change
 * queued offline, then another device saved before the console came back
 * online. The queued upload is held, then the choice applies to it. */
static void a_divergent_queued_upload_is_held_then_the_choice_applies_to_it(void)
{
    harness *h = h_new();
    write_local(h, save(1));
    prepare(h, "IRBF", RS_OK);
    h->now += HOUR;
    write_local(h, save(3));
    h->server.online = false;
    CHECK(prepare(h, "IRBF", RS_OK).offline); /* seen and queued, offline */
    h->server.online = true;
    fake_add_version(&h->server, "IRBF", save(2), 512, h->now + 30 * MINUTE); /* other device */
    int requests = h->server.upload_requests;

    rs_flush_result f;
    CHECK_INT(rs_engine_flush(&h->engine, &f, NULL), RS_OK);
    CHECK_INT(h->server.upload_requests, requests); /* never sent automatically */
    CHECK_INT(f.held, 1);
    CHECK_STR(f.first_held.game_id, "IRBF");
    CHECK(h->queue.items[0].held);
    CHECK_INT(h->last_event, RS_EVENT_NEEDS_CHOICE);
    CHECK_INT(rs_compute_status(false, false, "x", NULL, NULL, 1, true, rs_queue_held_for(&h->queue, h->save_path)),
              RS_STATUS_DIVERGED);

    /* Later flushes keep it without announcing it again. */
    h->last_event = RS_EVENT_UP_TO_DATE;
    CHECK_INT(rs_engine_flush(&h->engine, &f, NULL), RS_OK);
    CHECK_INT(f.held, 1);
    CHECK_INT(h->last_event, RS_EVENT_UP_TO_DATE);

    /* The held upload survives a restart; the choice applies to it. */
    h_open(h);
    CHECK(h->queue.items[0].held);
    CHECK(prepare(h, "IRBF", RS_OK).needs_choice);
    rs_prepare_result r = prepare_choice(h, "IRBF", RS_CHOICE_LOCAL, RS_OK);
    CHECK(r.uploaded);
    CHECK_INT(h->queue.count, 0);
    CHECK(active_is(h, "IRBF", save(3)));
    int copies = 0;
    char sha[65];
    rs_sha256_hex(save(3), 512, sha);
    for (int i = 0; i < h->server.version_count; i++)
        copies += strcmp(h->server.versions[i].sha, sha) == 0;
    CHECK_INT(copies, 1); /* sent once */
    h_free(h);
}

static void offline_queues_and_sends_on_reconnection_with_the_same_id(void)
{
    harness *h = h_new();
    write_local(h, save(1));
    prepare(h, "IRBF", RS_OK);
    h->now += MINUTE;
    write_local(h, save(2));
    h->server.online = false;

    rs_prepare_result r = prepare(h, "IRBF", RS_OK);
    CHECK(r.offline);
    CHECK(strstr(r.message, "injoignable") != NULL);
    CHECK_INT(h->queue.count, 1);
    char id[37];
    rs_strlcpy(id, h->queue.items[0].upload_id, sizeof id);

    h_open(h); /* the queue survives a restart */
    CHECK_INT(h->queue.count, 1);
    CHECK_STR(h->queue.items[0].upload_id, id);

    h->server.online = true;
    rs_flush_result f;
    CHECK_INT(rs_engine_flush(&h->engine, &f, NULL), RS_OK);
    CHECK_INT(f.sent, 1);
    CHECK_STR(h->server.upload_ids[h->server.upload_id_count - 1].upload_id, id);
    CHECK(active_is(h, "IRBF", save(2)));
    h_free(h);
}

static void a_retry_after_a_lost_response_creates_no_duplicate(void)
{
    harness *h = h_new();
    write_local(h, save(1));
    h->server.drop_next_upload_response = true;
    rs_prepare_result r = prepare(h, "IRBF", RS_OK);
    CHECK(r.offline);
    CHECK_INT(h->server.version_count, 1); /* created before the cut */

    rs_flush_result f;
    rs_engine_flush(&h->engine, &f, NULL);
    CHECK_INT(f.sent, 1);
    CHECK_INT(h->server.version_count, 1);
    CHECK_INT(rs_state_get(&h->states, h->save_path)->version_id, h->server.versions[0].id);
    h_free(h);
}

static void uploads_queued_offline_chain_their_base_versions(void)
{
    harness *h = h_new();
    rs_entry e = h_entry(h, "IRBF");
    h->server.online = false;
    rs_local_save s;
    write_local(h, save(1));
    rs_read_local_save(&e, &s, NULL);
    rs_engine_enqueue(&h->engine, &e, &s, NULL, NULL);
    rs_local_save_free(&s);
    h->now += MINUTE;
    write_local(h, save(2));
    rs_read_local_save(&e, &s, NULL);
    rs_engine_enqueue(&h->engine, &e, &s, NULL, NULL);
    rs_local_save_free(&s);

    h->server.online = true;
    rs_flush_result f;
    rs_engine_flush(&h->engine, &f, NULL);
    CHECK_INT(h->server.version_count, 2);
    CHECK_INT(h->server.versions[0].base, 0);
    CHECK_INT(h->server.versions[1].base, h->server.versions[0].id);
    CHECK(!h->server.versions[0].conflict && !h->server.versions[1].conflict);
    h_free(h);
}

static void the_same_content_is_queued_once(void)
{
    harness *h = h_new();
    rs_entry e = h_entry(h, "IRBF");
    write_local(h, save(1));
    rs_local_save s;
    rs_read_local_save(&e, &s, NULL);
    bool queued;
    rs_engine_enqueue(&h->engine, &e, &s, &queued, NULL);
    CHECK(queued);
    rs_engine_enqueue(&h->engine, &e, &s, &queued, NULL);
    CHECK(!queued);
    CHECK_INT(h->queue.count, 1);
    rs_local_save_free(&s);
    h_free(h);
}

static void an_upload_refused_by_the_server_is_kept_aside(void)
{
    harness *h = h_new();
    write_local(h, save(1));
    rs_strlcpy(h->server.refuse_uploads, "size_mismatch", sizeof h->server.refuse_uploads);
    prepare(h, "IRBF", RS_ERR_REFUSED);
    CHECK_INT(h->queue.count, 0);
    char failed[RS_PATH_MAX];
    snprintf(failed, sizeof failed, "%s/queue/failed", h->dir);
    CHECK(rs_dir_exists(failed));
    CHECK_INT(h->last_event, RS_EVENT_FAILED);
    h_free(h);
}

static void keeps_the_configured_number_of_backup_copies(void)
{
    harness *h = h_new();
    for (int i = 0; i < 4; i++) {
        write_local(h, save(10 + i));
        h->now += MINUTE;
        rs_backup(h->save_path, h->now, 2, NULL, 0, NULL);
    }
    char newest[RS_PATH_MAX];
    CHECK_INT(rs_backup_count(h->save_path, newest, sizeof newest), 2);
    CHECK(file_is(newest, save(13))); /* newest first */
    h_free(h);
}

static void the_offline_pass_queues_changes_without_the_network(void)
{
    harness *h = h_new();
    write_local(h, save(1));
    prepare(h, "IRBF", RS_OK);
    h->now += MINUTE;
    write_local(h, save(2));
    h->server.online = false;
    rs_entry e = h_entry(h, "IRBF");
    rs_prepare_result r;
    CHECK_INT(rs_engine_offline_pass(&h->engine, &e, &r, NULL), RS_OK);
    CHECK(r.offline);
    CHECK_INT(h->queue.count, 1);
    CHECK_INT(rs_engine_offline_pass(&h->engine, &e, &r, NULL), RS_OK);
    CHECK_INT(h->queue.count, 1); /* same content: queued once */
    h_free(h);
}

/* ---- Shared identifiers ------------------------------------------------ */

static void a_rom_waiting_for_a_choice_is_not_synced(void)
{
    harness *h = h_new();
    write_local(h, save(1));
    rs_entry e = h_entry(h, "CPUF");
    e.needs_choice = true;
    rs_prepare_result r;
    rs_error err;
    CHECK_INT(rs_engine_prepare(&h->engine, &e, 0, RS_CHOICE_NONE, &r, &err), RS_ERR_REFUSED);
    CHECK(strstr(err.message, "partager ou séparer") != NULL);
    CHECK_INT(h->server.upload_requests, 0);
    CHECK_INT(rs_compute_status(true, false, "x", NULL, NULL, 0, true, false), RS_STATUS_NEEDS_CHOICE);
    h_free(h);
}

static void a_state_recorded_under_another_identifier_is_ignored(void)
{
    harness *h = h_new();
    write_local(h, save(1));
    prepare(h, "CPUF", RS_OK);
    CHECK(rs_state_for(&h->states, h->save_path, "CPUF") != NULL);
    CHECK(rs_state_for(&h->states, h->save_path, "x:platine-patch") == NULL);
    h_free(h);
}

/* ---- Status ------------------------------------------------------------ */

static void compute_status_covers_every_state_of_the_game_list(void)
{
    rs_remote_game game = {.has_active = true, .active = {.id = 5}};
    rs_remote_game unknown = {0};
    rs_save_state synced = {.version_id = 5};
    rs_strlcpy(synced.hash, "h", sizeof synced.hash);
    rs_save_state older = {.version_id = 4};
    rs_strlcpy(older.hash, "h", sizeof older.hash);

    CHECK_INT(rs_compute_status(false, false, "h", &synced, &game, 0, true, false), RS_STATUS_UP_TO_DATE);
    CHECK_INT(rs_compute_status(false, false, "other", &synced, &game, 0, true, false), RS_STATUS_TO_UPLOAD);
    CHECK_INT(rs_compute_status(false, false, "h", &synced, &game, 1, true, false), RS_STATUS_TO_UPLOAD);
    CHECK_INT(rs_compute_status(false, false, "h", &older, &game, 0, true, false), RS_STATUS_TO_DOWNLOAD);
    CHECK_INT(rs_compute_status(false, false, NULL, NULL, &game, 0, true, false), RS_STATUS_TO_DOWNLOAD);
    CHECK_INT(rs_compute_status(false, false, "h", NULL, NULL, 0, true, false), RS_STATUS_TO_UPLOAD);
    CHECK_INT(rs_compute_status(false, false, "h", NULL, &unknown, 0, true, false), RS_STATUS_TO_UPLOAD);
    CHECK_INT(rs_compute_status(false, false, NULL, NULL, NULL, 0, true, false), RS_STATUS_NO_SAVE);
    CHECK_INT(rs_compute_status(false, false, "h", &synced, NULL, 0, false, false), RS_STATUS_OFFLINE);
    CHECK_INT(rs_compute_status(false, false, "other", &synced, NULL, 0, false, false), RS_STATUS_TO_UPLOAD);
    CHECK_INT(rs_compute_status(false, true, "h", NULL, NULL, 0, true, false), RS_STATUS_UNAVAILABLE);
    CHECK_INT(rs_compute_status(false, false, "h", &synced, &game, 1, true, true), RS_STATUS_DIVERGED);
}

/* ---- 3DS: clock ------------------------------------------------------- */

/* The console clock is 2 hours late. Another device saved 5 minutes ago,
 * the 3DS downloaded that save and the game was just played. Without the
 * correction, the 3DS save would be dated 2 hours ago and lose against the
 * other device's. */
static void a_late_console_clock_is_corrected_from_the_server_date(void)
{
    harness *h = h_new();
    rs_time real = h->now;
    h->server.server_now = real;
    fake_add_version(&h->server, "IRBF", save(2), 512, real - 5 * MINUTE); /* other device */
    h->now = real - 2 * HOUR;                                               /* late console */
    CHECK(prepare(h, "IRBF", RS_OK).downloaded);
    write_local(h, save(3));

    rs_prepare_result r = prepare(h, "IRBF", RS_OK);
    CHECK(r.uploaded && !r.downloaded);
    CHECK(active_is(h, "IRBF", save(3)));
    CHECK_INT(fake_active(&h->server, "IRBF")->saved_at, real);
    CHECK(h->states.clock.known);
    CHECK_INT(h->states.clock.offset, 2 * HOUR);
    h_free(h);
}

/* Offline, the last measured gap is used, even after a restart. */
static void offline_uploads_use_the_last_measured_gap(void)
{
    harness *h = h_new();
    rs_time real = h->now;
    h->server.server_now = real;
    h->now = real - 2 * HOUR;
    write_local(h, save(1));
    prepare(h, "IRBF", RS_OK); /* measures the gap and saves it with the state */

    h_open(h);
    CHECK_INT(h->states.clock.offset, 2 * HOUR);
    h->server.online = false;
    write_local(h, save(2));
    prepare(h, "IRBF", RS_OK);
    CHECK_INT(h->queue.count, 1);
    CHECK_INT(h->queue.items[0].saved_at, real);
    h_free(h);
}

/* ---- 3DS: save slot change -------------------------------------------- */

/* The game now uses another TWiLight Menu++ save slot (.sav1). Its file
 * exists but was never synced for this game: it is an old save, flagged so
 * that the user can set it aside instead of sending it. */
static void a_new_save_slot_with_an_old_file_is_flagged_and_can_be_set_aside(void)
{
    harness *h = h_new();
    write_local(h, save(1));
    prepare(h, "IRBF", RS_OK);
    rs_entry slot0 = h_entry(h, "IRBF");
    CHECK(!rs_is_stale_save(&slot0, &h->states));

    rs_entry slot1 = h_entry(h, "IRBF");
    snprintf(slot1.save_path, sizeof slot1.save_path, "%s/roms/saves/Game.sav1", h->dir);
    t_write(slot1.save_path, save(7), 512);
    CHECK(rs_is_stale_save(&slot1, &h->states));

    char copy[RS_PATH_MAX];
    CHECK_INT(rs_set_aside(slot1.save_path, h->now, 10, copy, sizeof copy, NULL), RS_OK);
    CHECK(!rs_file_exists(slot1.save_path));
    CHECK(file_is(copy, save(7)));
    CHECK(!rs_is_stale_save(&slot1, &h->states)); /* nothing left to flag */

    /* The new slot then follows the normal rule: the active version is
     * downloaded into it. */
    rs_prepare_result r;
    CHECK_INT(rs_engine_prepare(&h->engine, &slot1, 0, RS_CHOICE_NONE, &r, NULL), RS_OK);
    CHECK(r.downloaded);
    CHECK(file_is(slot1.save_path, save(1)));
    h_free(h);
}

void run_sync_tests(void)
{
    RUN(first_save_of_an_unknown_game_is_uploaded);
    RUN(unchanged_local_and_newer_server_version_downloads_with_backup);
    RUN(no_local_save_downloads_the_server_version);
    RUN(local_save_identical_to_the_server_means_no_transfer);
    RUN(up_to_date_does_nothing);
    RUN(local_change_with_the_server_unchanged_is_sent_without_question);
    RUN(divergence_sends_and_overwrites_nothing_until_the_user_chooses);
    RUN(choice_local_is_sent_and_active_even_when_older);
    RUN(choice_server_archives_the_local_save_then_downloads_with_backup);
    RUN(a_choice_against_a_server_too_old_for_x_activate_is_refused);
    RUN(first_sync_of_a_console_whose_save_differs_from_the_server_is_a_divergence);
    RUN(an_upload_right_after_a_download_is_never_divergent);
    RUN(a_save_padded_with_zeros_with_the_active_content_is_no_divergence);
    RUN(a_smaller_save_whose_active_version_only_adds_padding_is_no_divergence);
    RUN(a_divergent_queued_upload_is_held_then_the_choice_applies_to_it);
    RUN(offline_queues_and_sends_on_reconnection_with_the_same_id);
    RUN(a_retry_after_a_lost_response_creates_no_duplicate);
    RUN(uploads_queued_offline_chain_their_base_versions);
    RUN(the_same_content_is_queued_once);
    RUN(an_upload_refused_by_the_server_is_kept_aside);
    RUN(keeps_the_configured_number_of_backup_copies);
    RUN(the_offline_pass_queues_changes_without_the_network);
    RUN(a_rom_waiting_for_a_choice_is_not_synced);
    RUN(a_state_recorded_under_another_identifier_is_ignored);
    RUN(compute_status_covers_every_state_of_the_game_list);
    RUN(a_late_console_clock_is_corrected_from_the_server_date);
    RUN(offline_uploads_use_the_last_measured_gap);
    RUN(a_new_save_slot_with_an_old_file_is_flagged_and_can_be_set_aside);
}
