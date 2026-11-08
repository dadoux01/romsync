/* test_profile.c - conversion profiles, read from the repository's
 * profiles/ folder, same cases as romsync_core's profile_test.dart. */
#include <stdlib.h>
#include <string.h>

#include "../core/profile.h"
#include "suites.h"
#include "test.h"

static rs_profiles profiles;

static uint8_t *pattern(size_t n)
{
    uint8_t *b = malloc(n);
    for (size_t i = 0; i < n; i++)
        b[i] = (uint8_t)((i * 31 + i / 251) & 0xFF);
    return b;
}

static void loads_the_repository_profiles(void)
{
    rs_error err;
    CHECK_INT(rs_profiles_load_dir(&profiles, t_repo("profiles"), &err), RS_OK);
    const char *ids[] = {"raw", "desmume", "flashcard", "retroarch-melondsds", "twilight"};
    for (int i = 0; i < 5; i++)
        CHECK(rs_profiles_find(&profiles, ids[i]) != NULL);
    CHECK_STR(rs_profiles_find(&profiles, "raw")->extension, ".sav");
    CHECK_STR(rs_profiles_find(&profiles, "desmume")->extension, ".dsv");
    CHECK_STR(rs_profiles_find(&profiles, "flashcard")->status, "to_verify");
    CHECK_STR(rs_profiles_find(&profiles, "twilight")->status, "to_verify");
}

static void raw_and_twilight_are_the_identity(void)
{
    uint8_t *raw = pattern(8192);
    rs_buf out = {0};
    const char *ids[] = {"raw", "twilight"};
    for (int i = 0; i < 2; i++) {
        const rs_profile *p = rs_profiles_find(&profiles, ids[i]);
        CHECK_INT(rs_profile_decode(p, raw, 8192, &out, NULL), RS_OK);
        CHECK(out.len == 8192 && memcmp(out.data, raw, 8192) == 0);
        CHECK_INT(rs_profile_encode(p, raw, 8192, 0, &out, NULL), RS_OK);
        CHECK(out.len == 8192 && memcmp(out.data, raw, 8192) == 0);
    }
    rs_buf_free(&out);
    free(raw);
}

/* Builds raw + footer read from a fixture cut from a real .dsv file. */
static void with_footer(const char *fixture, const uint8_t *raw, size_t n, rs_buf *file)
{
    rs_buf footer = {0};
    CHECK_INT(rs_read_file(t_repo(fixture), &footer, NULL), RS_OK);
    file->len = 0;
    rs_buf_append(file, raw, n);
    rs_buf_append(file, footer.data, footer.len);
    rs_buf_free(&footer);
}

static void desmume_footer_is_byte_identical(void)
{
    const rs_profile *dsm = rs_profiles_find(&profiles, "desmume");
    size_t n = 512 << 10;
    uint8_t *raw = pattern(n);
    rs_buf real = {0}, out = {0};
    with_footer("server/internal/convert/testdata/desmume_footer_512k.bin", raw, n, &real);
    CHECK_INT(rs_profile_decode(dsm, real.data, real.len, &out, NULL), RS_OK);
    CHECK(out.len == n && memcmp(out.data, raw, n) == 0);
    CHECK_INT(rs_profile_encode(dsm, raw, n, 0, &out, NULL), RS_OK);
    CHECK(out.len == real.len && memcmp(out.data, real.data, real.len) == 0);
    rs_buf_free(&real);
    rs_buf_free(&out);
    free(raw);
}

static void desmume_decode_ignores_type_and_checks_the_rest(void)
{
    const rs_profile *dsm = rs_profiles_find(&profiles, "desmume");
    size_t n = 512 << 10;
    uint8_t *raw = pattern(n);
    rs_buf file = {0}, out = {0};
    with_footer("server/internal/convert/testdata/desmume_footer_512k_type0.bin", raw, n, &file);
    CHECK_INT(rs_profile_decode(dsm, file.data, file.len, &out, NULL), RS_OK);
    CHECK(out.len == n && memcmp(out.data, raw, n) == 0);
    /* No footer at all. */
    CHECK_INT(rs_profile_decode(dsm, raw, n, &out, NULL), RS_ERR_FORMAT);
    /* A footer announcing 512 bytes after 522 bytes of data. */
    rs_buf small = {0};
    rs_profile_encode(dsm, raw, 512, 0, &small, NULL);
    file.len = 0;
    rs_buf_append(&file, raw, 10);
    rs_buf_append(&file, small.data, small.len);
    CHECK_INT(rs_profile_decode(dsm, file.data, file.len, &out, NULL), RS_ERR_FORMAT);
    rs_buf_free(&small);
    rs_buf_free(&file);
    rs_buf_free(&out);
    free(raw);
}

static void decoding_never_cuts_the_save(void)
{
    size_t n = 512 << 10;
    uint8_t *half = calloc(1, n);
    memset(half + n / 2, 0xFF, n / 2);
    rs_buf out = {0}, enc = {0};
    const char *ids[] = {"raw", "flashcard", "twilight"};
    for (int i = 0; i < 3; i++) {
        rs_profile_decode(rs_profiles_find(&profiles, ids[i]), half, n, &out, NULL);
        CHECK_INT(out.len, n);
    }
    const rs_profile *dsm = rs_profiles_find(&profiles, "desmume");
    rs_profile_encode(dsm, half, n, 0, &enc, NULL);
    rs_profile_decode(dsm, enc.data, enc.len, &out, NULL);
    CHECK_INT(out.len, n);
    rs_buf_free(&out);
    rs_buf_free(&enc);
    free(half);
}

static void flashcard_pads_and_never_cuts(void)
{
    const rs_profile *fc = rs_profiles_find(&profiles, "flashcard");
    size_t n = 64 << 10;
    uint8_t *small = pattern(n);
    rs_buf out = {0};
    rs_profile_encode(fc, small, n, 0, &out, NULL);
    CHECK_INT(out.len, 512 << 10);
    CHECK(memcmp(out.data, small, n) == 0);
    bool all_ff = true;
    for (size_t i = n; i < out.len; i++)
        all_ff = all_ff && out.data[i] == 0xFF;
    CHECK(all_ff);
    uint8_t *big = pattern(1 << 20);
    rs_profile_encode(fc, big, 1 << 20, 0, &out, NULL);
    CHECK_INT(out.len, 1 << 20);
    rs_profile_encode(fc, small, n, 1 << 20, &out, NULL);
    CHECK_INT(out.len, 1 << 20);
    rs_buf_free(&out);
    free(small);
    free(big);
}

static void sd_card_profiles_override_bundled_ones(void)
{
    const char *dir = t_tmpdir();
    char path[512];
    snprintf(path, sizeof path, "%s/twilight.json", dir);
    const char *json = "{\"id\":\"twilight\",\"name\":\"Mine\",\"status\":\"confirmed\","
                       "\"extension\":\".sav\",\"header\":null,\"footer\":null,"
                       "\"size\":{\"output\":\"exact\"}}";
    t_write(path, json, strlen(json));
    int before = profiles.count;
    CHECK_INT(rs_profiles_load_dir(&profiles, dir, NULL), RS_OK);
    CHECK_INT(profiles.count, before);
    CHECK_STR(rs_profiles_find(&profiles, "twilight")->name, "Mine");
    t_rmtree(dir);
}

static void rejects_malformed_profiles(void)
{
    rs_profile p;
    rs_error err;
    CHECK_INT(rs_profile_parse("{", &p, &err), RS_ERR_FORMAT);
    CHECK_INT(rs_profile_parse("{\"id\":\"x\",\"name\":\"x\",\"status\":\"x\",\"extension\":\".x\","
                               "\"header\":{\"length\":4}}",
                               &p, &err),
              RS_ERR_FORMAT);
    /* The declared footer length must match its parts. */
    CHECK_INT(rs_profile_parse("{\"id\":\"x\",\"name\":\"x\",\"status\":\"x\",\"extension\":\".x\","
                               "\"footer\":{\"length\":5,\"prefix\":\"ab\",\"cookie\":\"cd\",\"fields\":[]}}",
                               &p, &err),
              RS_ERR_FORMAT);
}

void run_profile_tests(void)
{
    RUN(loads_the_repository_profiles);
    RUN(raw_and_twilight_are_the_identity);
    RUN(desmume_footer_is_byte_identical);
    RUN(desmume_decode_ignores_type_and_checks_the_rest);
    RUN(decoding_never_cuts_the_save);
    RUN(flashcard_pads_and_never_cuts);
    RUN(sd_card_profiles_override_bundled_ones);
    RUN(rejects_malformed_profiles);
    rs_profiles_free(&profiles);
}
