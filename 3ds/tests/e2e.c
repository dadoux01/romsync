/*
 * e2e.c - end-to-end test of the C core against the real Go server, over
 * HTTP with libcurl, like romsync_core's e2e test. Started by e2e.sh, which
 * builds and runs the server and creates two pairing codes:
 *
 *   e2e <server url> <pairing code 1> <pairing code 2> <work folder>
 *
 * Two devices share a game: "3DS" (the homebrew's rules) and "PC".
 */
#include <curl/curl.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#include "../core/platform.h"
#include "../core/sha.h"
#include "../core/sync.h"
#include "test.h"

int t_failures = 0;
int t_checks = 0;
const char *t_current = "";

#define GAME "x:e2e-3ds"
#define SAVE_SIZE 8192

typedef struct {
    const char *name;
    char dir[RS_PATH_MAX];
    rs_profile profile;
    rs_state_store states;
    rs_queue queue;
    rs_api api;
    rs_engine engine;
    rs_entry entry;
    int64_t clock_shift; /* seconds added to the real clock (late console < 0) */
} device;

static rs_time device_now(void *ctx)
{
    return (rs_time)time(NULL) + ((device *)ctx)->clock_shift;
}

static void setup_device(device *d, const char *name, const char *url, const char *code, const char *work)
{
    memset(d, 0, sizeof *d);
    d->name = name;
    rs_path_join(d->dir, sizeof d->dir, work, name);
    char path[RS_PATH_MAX];
    rs_path_join(path, sizeof path, d->dir, "state.json");
    CHECK_INT(rs_state_open(&d->states, path, NULL), RS_OK);
    rs_path_join(path, sizeof path, d->dir, "queue");
    CHECK_INT(rs_queue_open(&d->queue, path, NULL), RS_OK);
    rs_profile_parse("{\"id\":\"twilight\",\"name\":\"TWiLight\",\"status\":\"to_verify\",\"extension\":\".sav\","
                     "\"size\":{\"output\":\"exact\"}}",
                     &d->profile, NULL);

    d->api = (rs_api){.send = rs_http_curl_send, .clock = &d->states.clock, .now = device_now, .now_ctx = d};
    CHECK(rs_api_normalize_url(url, d->api.base_url, sizeof d->api.base_url));
    rs_error err = {0};
    rs_status st = rs_api_pair(&d->api, code, name, strcmp(name, "3DS") == 0 ? "3ds" : "linux", d->api.token,
                               sizeof d->api.token, &err);
    CHECK_INT(st, RS_OK);
    if (st != RS_OK)
        fprintf(stderr, "pair: %s\n", err.message);

    d->engine = (rs_engine){.api = &d->api, .states = &d->states, .queue = &d->queue, .keep_backups = 10,
                            .now = device_now, .now_ctx = d};
    rs_strlcpy(d->entry.game_id, GAME, sizeof d->entry.game_id);
    rs_strlcpy(d->entry.title, "E2E 3DS", sizeof d->entry.title);
    rs_path_join(d->entry.save_path, sizeof d->entry.save_path, d->dir, "roms/saves/Game.sav");
    rs_path_join(d->entry.rom_path, sizeof d->entry.rom_path, d->dir, "roms/Game.nds");
    d->entry.profile = &d->profile;
    rs_strlcpy(d->entry.emulator, strcmp(name, "3DS") == 0 ? "twilight" : "melonds", sizeof d->entry.emulator);
}

static void free_device(device *d)
{
    rs_state_close(&d->states);
    rs_queue_close(&d->queue);
    rs_profile_free(&d->profile);
}

static const uint8_t *save(int seed)
{
    static uint8_t b[4][SAVE_SIZE];
    static int next;
    uint8_t *out = b[next++ % 4];
    for (int i = 0; i < SAVE_SIZE; i++)
        out[i] = (uint8_t)((i * 13 + seed * 7) & 0xFF);
    return out;
}

static void write_save(device *d, const uint8_t *data, size_t len)
{
    t_write(d->entry.save_path, data, len);
}

static bool save_is(device *d, const uint8_t *data)
{
    rs_buf b = {0};
    bool same = rs_read_file(d->entry.save_path, &b, NULL) == RS_OK && b.len == SAVE_SIZE &&
                memcmp(b.data, data, SAVE_SIZE) == 0;
    rs_buf_free(&b);
    return same;
}

/* Dates are sent to the second, and the server keeps the active version on
 * a tie: wait before a save that must come after the previous one. */
static void next_second(void)
{
    sleep(1);
}

static rs_prepare_result prepare(device *d)
{
    rs_prepare_result r;
    rs_error err = {0};
    rs_status st = rs_engine_prepare(&d->engine, &d->entry, 0, &r, &err);
    CHECK_INT(st, RS_OK);
    if (st != RS_OK)
        fprintf(stderr, "    %s: %s\n", d->name, err.message);
    return r;
}

static rs_version active(device *d)
{
    rs_version v = {0};
    bool exists = false;
    CHECK_INT(rs_api_active(&d->api, GAME, &v, &exists, NULL), RS_OK);
    CHECK(exists);
    return v;
}

static device ds, pc;

static void the_3ds_uploads_its_first_save(void)
{
    write_save(&ds, save(1), SAVE_SIZE);
    rs_prepare_result r = prepare(&ds);
    CHECK(r.uploaded);
    rs_version v = active(&ds);
    CHECK_INT(v.size, SAVE_SIZE);
    CHECK_STR(v.device_name, "3DS");
    /* The server's Date header was read: the console clock is right here. */
    CHECK(ds.states.clock.known);
    CHECK(ds.states.clock.offset >= -5 && ds.states.clock.offset <= 5);
}

static void the_pc_downloads_it(void)
{
    rs_prepare_result r = prepare(&pc);
    CHECK(r.downloaded);
    CHECK(save_is(&pc, save(1)));
}

static void the_3ds_downloads_the_pc_save_at_startup_with_a_backup(void)
{
    next_second();
    write_save(&pc, save(2), SAVE_SIZE);
    CHECK(prepare(&pc).uploaded);
    rs_prepare_result r = prepare(&ds);
    CHECK(r.downloaded);
    CHECK(save_is(&ds, save(2)));
    CHECK(r.backup_path[0] != 0);
}

/* TWiLight Menu++ grows the save to its own size with zeros at launch. The
 * server cuts the zeros: same content as the active version, no new one. */
static void padding_added_by_twilight_menu_creates_no_version(void)
{
    rs_version before = active(&ds);
    uint8_t *padded = calloc(1, 512 * 1024);
    memcpy(padded, save(2), SAVE_SIZE);
    write_save(&ds, padded, 512 * 1024);
    free(padded);
    rs_prepare_result r = prepare(&ds);
    CHECK(!r.downloaded);
    CHECK_INT(active(&ds).id, before.id);
    /* The padded file is now the synced state: nothing more to send. */
    r = prepare(&ds);
    CHECK(!r.uploaded && !r.downloaded);
}

static void offline_play_is_queued_and_sent_with_the_same_id(void)
{
    char url[256];
    rs_strlcpy(url, ds.api.base_url, sizeof url);
    rs_strlcpy(ds.api.base_url, "http://127.0.0.1:9", sizeof ds.api.base_url); /* nothing listens */
    next_second();
    write_save(&ds, save(3), SAVE_SIZE);
    rs_prepare_result r = prepare(&ds);
    CHECK(r.offline);
    CHECK_INT(ds.queue.count, 1);
    char id[37];
    rs_strlcpy(id, ds.queue.items[0].upload_id, sizeof id);

    rs_strlcpy(ds.api.base_url, url, sizeof ds.api.base_url);
    rs_flush_result f;
    CHECK_INT(rs_engine_flush(&ds.engine, &f, NULL), RS_OK);
    CHECK_INT(f.sent, 1);
    rs_version v = active(&ds);
    char sha[65];
    rs_sha256_hex(save(3), SAVE_SIZE, sha);
    CHECK_STR(v.sha256, sha);

    /* Sending the same upload id again returns the same version. */
    rs_upload_result again;
    CHECK_INT(rs_api_upload(&ds.api, GAME, save(3), SAVE_SIZE, time(NULL), id, 0, "twilight", NULL, &again, NULL),
              RS_OK);
    CHECK_INT(again.version.id, v.id);
}

/* The console is 3 hours late. The PC saved 10 minutes ago; the 3DS game
 * is played after it. The corrected date makes the 3DS save win. */
static void a_late_3ds_clock_does_not_lose_the_3ds_save(void)
{
    CHECK(prepare(&pc).downloaded);
    next_second();
    write_save(&pc, save(4), SAVE_SIZE);
    CHECK(prepare(&pc).uploaded);
    CHECK(prepare(&ds).downloaded);

    ds.clock_shift = -3 * 3600;
    next_second();
    write_save(&ds, save(5), SAVE_SIZE);
    rs_prepare_result r = prepare(&ds);
    CHECK(r.uploaded && !r.downloaded);
    CHECK(ds.states.clock.offset >= 3 * 3600 - 5 && ds.states.clock.offset <= 3 * 3600 + 5);
    rs_version v = active(&ds);
    char sha[65];
    rs_sha256_hex(save(5), SAVE_SIZE, sha);
    CHECK_STR(v.sha256, sha);
    rs_time now = time(NULL);
    CHECK(v.saved_at >= now - 60 && v.saved_at <= now + 5);
}

static void the_game_list_shows_the_game(void)
{
    rs_remote_game *games;
    int n;
    CHECK_INT(rs_api_games(&ds.api, &games, &n, NULL), RS_OK);
    bool found = false;
    for (int i = 0; i < n; i++)
        if (strcmp(games[i].code, GAME) == 0) {
            found = true;
            CHECK_STR(games[i].title, "E2E 3DS");
            CHECK(games[i].has_active);
            CHECK_INT(games[i].chip_size, SAVE_SIZE);
        }
    CHECK(found);
    free(games);
}

static void a_revoked_or_wrong_token_is_refused(void)
{
    rs_api bad = ds.api;
    rs_strlcpy(bad.token, "not-a-token", sizeof bad.token);
    rs_version v;
    bool exists;
    rs_error err = {0};
    CHECK_INT(rs_api_active(&bad, GAME, &v, &exists, &err), RS_ERR_API);
    CHECK_INT(err.http_status, 401);
    CHECK_STR(err.code, "unauthorized");
}

int main(int argc, char **argv)
{
    if (argc != 5) {
        fprintf(stderr, "usage: e2e <url> <code1> <code2> <work dir>\n");
        return 2;
    }
    curl_global_init(CURL_GLOBAL_DEFAULT);
    setup_device(&ds, "3DS", argv[1], argv[2], argv[4]);
    setup_device(&pc, "PC", argv[1], argv[3], argv[4]);
    if (t_failures == 0) {
        RUN(the_3ds_uploads_its_first_save);
        RUN(the_pc_downloads_it);
        RUN(the_3ds_downloads_the_pc_save_at_startup_with_a_backup);
        RUN(padding_added_by_twilight_menu_creates_no_version);
        RUN(offline_play_is_queued_and_sent_with_the_same_id);
        RUN(a_late_3ds_clock_does_not_lose_the_3ds_save);
        RUN(the_game_list_shows_the_game);
        RUN(a_revoked_or_wrong_token_is_refused);
    }
    free_device(&ds);
    free_device(&pc);
    curl_global_cleanup();
    printf("e2e: %d checks, %d failures\n", t_checks, t_failures);
    return t_failures ? 1 : 0;
}

/* test.h helper used here (the unit tests' main.c is not linked). */
void t_write(const char *path, const void *data, size_t len)
{
    rs_error err;
    if (rs_write_file_atomic(path, data, len, &err) != RS_OK) {
        fprintf(stderr, "t_write: %s\n", err.message);
        exit(2);
    }
}
