/* test_state.c - dates, state store, upload queue and JSON files, same
 * cases as romsync_core's state_test.dart where they apply. */
#include <stdlib.h>
#include <string.h>

#include "../core/clock.h"
#include "../core/json_file.h"
#include "../core/queue.h"
#include "../core/state.h"
#include "suites.h"
#include "test.h"

static void formats_and_parses_iso_dates(void)
{
    char s[32];
    rs_time_format_iso(0, s, sizeof s);
    CHECK_STR(s, "1970-01-01T00:00:00Z");
    rs_time_format_iso(1794052800, s, sizeof s);
    CHECK_STR(s, "2026-11-07T12:00:00Z");
    rs_time_format_iso(951782400, s, sizeof s); /* leap day */
    CHECK_STR(s, "2000-02-29T00:00:00Z");

    rs_time t;
    CHECK(rs_time_parse_iso("2026-11-07T12:00:00Z", &t));
    CHECK_INT(t, 1794052800);
    CHECK(rs_time_parse_iso("2026-11-07T12:00:00.123456Z", &t)); /* Go's format */
    CHECK_INT(t, 1794052800);
    CHECK(rs_time_parse_iso("2026-11-07T13:00:00+01:00", &t));
    CHECK_INT(t, 1794052800);
    CHECK(!rs_time_parse_iso("2026-11-07", &t));
    CHECK(!rs_time_parse_iso("2026-13-07T12:00:00Z", &t));
    CHECK(!rs_time_parse_iso("", &t));
}

static void parses_http_dates(void)
{
    rs_time t;
    CHECK(rs_time_parse_http("Sat, 07 Nov 2026 12:00:00 GMT", &t));
    CHECK_INT(t, 1794052800);
    CHECK(!rs_time_parse_http("", &t));
    CHECK(!rs_time_parse_http("Sat, 07 Foo 2026 12:00:00 GMT", &t));
}

static void corrects_the_console_clock(void)
{
    rs_clock c = {0};
    CHECK_INT(rs_clock_correct(&c, 1000), 1000); /* unknown gap: unchanged */
    rs_clock_observe(&c, 8200, 1000);           /* console 2 h late */
    CHECK_INT(rs_clock_correct(&c, 1500), 8700);
    rs_clock_observe(&c, 1000, 4600); /* console 1 h ahead */
    CHECK_INT(rs_clock_correct(&c, 4600), 1000);
}

static void state_store_keeps_one_state_per_save_file(void)
{
    const char *dir = t_tmpdir();
    char path[512];
    snprintf(path, sizeof path, "%s/state.json", dir);
    rs_state_store s;
    CHECK_INT(rs_state_open(&s, path, NULL), RS_OK);
    CHECK_INT(s.count, 0);
    rs_state_record(&s, "sdmc:/roms/a.sav", "IRBF", 4, "h1", 100, NULL);
    rs_state_record(&s, "sdmc:/roms/b.sav", "CPUF", 7, "h2", 200, NULL);
    rs_clock_observe(&s.clock, 1000, 400);
    rs_state_save(&s, NULL);
    rs_state_close(&s);

    CHECK_INT(rs_state_open(&s, path, NULL), RS_OK);
    CHECK_INT(rs_state_get(&s, "sdmc:/roms/a.sav")->version_id, 4);
    CHECK_STR(rs_state_get(&s, "sdmc:/roms/b.sav")->hash, "h2");
    CHECK_STR(rs_state_get(&s, "sdmc:/roms/b.sav")->game_id, "CPUF");
    CHECK_INT(rs_state_get(&s, "sdmc:/roms/b.sav")->synced_at, 200);
    CHECK(s.clock.known);
    CHECK_INT(s.clock.offset, 600);
    rs_state_forget(&s, "sdmc:/roms/a.sav", NULL);
    rs_state_close(&s);
    CHECK_INT(rs_state_open(&s, path, NULL), RS_OK);
    CHECK(rs_state_get(&s, "sdmc:/roms/a.sav") == NULL);
    rs_state_close(&s);
    t_rmtree(dir);
}

static void a_corrupted_file_is_moved_aside(void)
{
    const char *dir = t_tmpdir();
    char path[512], aside[520];
    snprintf(path, sizeof path, "%s/state.json", dir);
    t_write(path, "{not json", 9);
    rs_state_store s;
    CHECK_INT(rs_state_open(&s, path, NULL), RS_OK);
    CHECK_INT(s.count, 0);
    CHECK(strstr(s.warning, "mis de côté") != NULL);
    snprintf(aside, sizeof aside, "%s.corrupt", path);
    CHECK(rs_file_exists(aside));
    rs_state_close(&s);
    t_rmtree(dir);
}

static bool is_uuid4(const char *s)
{
    if (strlen(s) != 36 || s[14] != '4')
        return false;
    for (int i = 0; i < 36; i++) {
        bool dash = i == 8 || i == 13 || i == 18 || i == 23;
        if (dash != (s[i] == '-'))
            return false;
        if (!dash && !strchr("0123456789abcdef", s[i]))
            return false;
    }
    return strchr("89ab", s[19]) != NULL;
}

static void upload_queue_persists_uploads_their_content_and_ids(void)
{
    const char *dir = t_tmpdir();
    char qdir[512];
    snprintf(qdir, sizeof qdir, "%s/queue", dir);
    rs_queue q;
    CHECK_INT(rs_queue_open(&q, qdir, NULL), RS_OK);
    uint8_t one[] = {1, 2}, two[] = {3};
    rs_upload a, b;
    rs_queue_add(&q, "IRBF", "/s/a.sav", one, 2, "h1", 100, "twilight", "POKEMON B", 101, &a, NULL);
    rs_queue_add(&q, "IRBF", "/s/a.sav", two, 1, "h2", 200, "twilight", NULL, 201, &b, NULL);
    CHECK(strcmp(a.upload_id, b.upload_id) != 0);
    CHECK(is_uuid4(a.upload_id));
    rs_queue_close(&q);

    rs_queue r;
    CHECK_INT(rs_queue_open(&r, qdir, NULL), RS_OK);
    CHECK_INT(r.count, 2);
    CHECK_STR(r.items[0].upload_id, a.upload_id);
    CHECK_STR(r.items[1].upload_id, b.upload_id);
    CHECK_INT(r.items[0].saved_at, 100);
    CHECK_STR(r.items[0].title, "POKEMON B");
    rs_buf content = {0};
    CHECK_INT(rs_queue_content(&r, &r.items[0], &content, NULL), RS_OK);
    CHECK(content.len == 2 && content.data[0] == 1 && content.data[1] == 2);
    rs_buf_free(&content);
    CHECK_INT(rs_queue_count_for(&r, "/s/a.sav"), 2);
    CHECK(rs_queue_has(&r, "/s/a.sav", "IRBF", "h2"));
    CHECK(!rs_queue_has(&r, "/s/a.sav", "CPUF", "h2"));

    rs_queue_remove(&r, a.upload_id, NULL);
    rs_queue_close(&r);
    CHECK_INT(rs_queue_open(&r, qdir, NULL), RS_OK);
    CHECK_INT(r.count, 1);
    CHECK_STR(r.items[0].upload_id, b.upload_id);
    char gone[600];
    snprintf(gone, sizeof gone, "%s/%s.bin", qdir, a.upload_id);
    CHECK(!rs_file_exists(gone));
    rs_queue_close(&r);
    t_rmtree(dir);
}

static void upload_queue_drops_entries_whose_content_is_missing(void)
{
    const char *dir = t_tmpdir();
    char qdir[512], bin[600];
    snprintf(qdir, sizeof qdir, "%s/queue", dir);
    rs_queue q;
    rs_queue_open(&q, qdir, NULL);
    rs_upload a;
    uint8_t one[] = {1};
    rs_queue_add(&q, "IRBF", "/s/a.sav", one, 1, "h1", 1, "", NULL, 1, &a, NULL);
    rs_queue_close(&q);
    snprintf(bin, sizeof bin, "%s/%s.bin", qdir, a.upload_id);
    remove(bin);
    rs_queue_open(&q, qdir, NULL);
    CHECK_INT(q.count, 0);
    rs_queue_close(&q);
    t_rmtree(dir);
}

void run_state_tests(void)
{
    RUN(formats_and_parses_iso_dates);
    RUN(parses_http_dates);
    RUN(corrects_the_console_clock);
    RUN(state_store_keeps_one_state_per_save_file);
    RUN(a_corrupted_file_is_moved_aside);
    RUN(upload_queue_persists_uploads_their_content_and_ids);
    RUN(upload_queue_drops_entries_whose_content_is_missing);
}
