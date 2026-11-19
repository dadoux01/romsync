/*
 * test_tree.c - saves made of a folder: the shared vectors of testdata/tree
 * give the same archive as the server and romsync_core.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../core/tree.h"
#include "../vendor/cjson/cJSON.h"
#include "suites.h"
#include "test.h"

static void load_vector(const char *name, rs_tree *t, rs_buf *want)
{
    char path[RS_PATH_MAX], rel[64];
    rs_buf json = {0};
    snprintf(rel, sizeof rel, "testdata/tree/%s.json", name);
    rs_strlcpy(path, t_repo(rel), sizeof path);
    CHECK_INT(rs_read_file(path, &json, NULL), RS_OK);
    rs_buf_terminate(&json);
    cJSON *doc = cJSON_Parse((const char *)json.data);
    memset(t, 0, sizeof *t);
    const cJSON *e;
    cJSON_ArrayForEach(e, cJSON_GetObjectItemCaseSensitive(doc, "entries"))
    {
        const char *p = cJSON_GetObjectItemCaseSensitive(e, "path")->valuestring;
        const cJSON *hex = cJSON_GetObjectItemCaseSensitive(e, "content_hex");
        size_t n = cJSON_IsString(hex) ? strlen(hex->valuestring) / 2 : 0;
        uint8_t *data = calloc(1, n + 1);
        for (size_t i = 0; i < n; i++) {
            unsigned v;
            sscanf(hex->valuestring + 2 * i, "%2x", &v);
            data[i] = (uint8_t)v;
        }
        CHECK(rs_tree_add(t, p, cJSON_IsString(hex) ? data : NULL, n));
        free(data);
    }
    cJSON_Delete(doc);
    rs_buf_free(&json);
    snprintf(rel, sizeof rel, "testdata/tree/%s.tar", name);
    rs_strlcpy(path, t_repo(rel), sizeof path);
    CHECK_INT(rs_read_file(path, want, NULL), RS_OK);
}

static bool equal(const rs_buf *a, const rs_buf *b)
{
    return a->len == b->len && memcmp(a->data, b->data, a->len) == 0;
}

static void the_shared_vectors_give_the_same_archive(void)
{
    const char *names[] = {"empty", "simple", "long-path"};
    for (int i = 0; i < 3; i++) {
        rs_tree t, back;
        rs_buf want = {0}, got = {0}, again = {0};
        load_vector(names[i], &t, &want);
        CHECK_INT(rs_tree_archive(&t, &got, NULL), RS_OK);
        CHECK(equal(&got, &want));
        CHECK_INT(rs_tree_parse(want.data, want.len, &back, NULL), RS_OK);
        CHECK_INT(rs_tree_archive(&back, &again, NULL), RS_OK);
        CHECK(equal(&again, &want));
        rs_tree_free(&t);
        rs_tree_free(&back);
        rs_buf_free(&want);
        rs_buf_free(&got);
        rs_buf_free(&again);
    }
}

static void invalid_entries_are_refused(void)
{
    const char *bad[] = {"/etc/passwd", "a/../b", "a//b", "./a"};
    for (int i = 0; i < 4; i++) {
        rs_tree t = {0};
        rs_buf out = {0};
        rs_tree_add(&t, bad[i], (const uint8_t *)"x", 1);
        CHECK_INT(rs_tree_archive(&t, &out, NULL), RS_ERR_FORMAT);
        rs_tree_free(&t);
        rs_buf_free(&out);
    }
    rs_tree dup = {0};
    rs_buf out = {0};
    rs_tree_add(&dup, "a", (const uint8_t *)"x", 1);
    rs_tree_add(&dup, "a/b", (const uint8_t *)"y", 1); /* "a" would be a file and a folder */
    CHECK_INT(rs_tree_archive(&dup, &out, NULL), RS_ERR_FORMAT);
    rs_tree_free(&dup);
    rs_buf_free(&out);
    rs_tree t;
    CHECK_INT(rs_tree_parse((const uint8_t *)"not a tar", 9, &t, NULL), RS_ERR_FORMAT);
}

static void a_folder_is_read_and_replaced(void)
{
    const char *base = t_tmpdir();
    char dir[RS_PATH_MAX], file[RS_PATH_MAX];
    rs_path_join(dir, sizeof dir, base, "save");
    rs_buf got = {0}, want = {0};
    bool exists = true;
    long long newest;
    CHECK_INT(rs_tree_read_dir(dir, &got, &exists, &newest, NULL), RS_OK);
    CHECK(!exists);

    /* Written from the vector, read back as the same archive. */
    rs_tree t;
    load_vector("simple", &t, &want);
    rs_path_join(file, sizeof file, dir, "stale.bin"); /* replaced by the write */
    t_write(file, "old", 3);
    CHECK_INT(rs_tree_write_dir(dir, want.data, want.len, NULL), RS_OK);
    CHECK(!rs_file_exists(file));
    rs_path_join(file, sizeof file, dir, "extra/sub/empty-dir");
    CHECK(rs_dir_exists(file));
    CHECK_INT(rs_tree_read_dir(dir, &got, &exists, &newest, NULL), RS_OK);
    CHECK(exists);
    CHECK(newest > 0);
    CHECK(equal(&got, &want));
    char aside[RS_PATH_MAX];
    snprintf(aside, sizeof aside, "%s.romsync-old", dir);
    CHECK(!rs_dir_exists(aside));

    rs_tree_free(&t);
    rs_buf_free(&got);
    rs_buf_free(&want);
    t_rmtree(base);
}

void run_tree_tests(void)
{
    RUN(the_shared_vectors_give_the_same_archive);
    RUN(invalid_entries_are_refused);
    RUN(a_folder_is_read_and_replaced);
}
