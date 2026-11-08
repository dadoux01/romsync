/*
 * main.c - runs every unit test of the core (Linux only).
 */
#define _XOPEN_SOURCE 700
#include <ftw.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "../core/rs.h"
#include "suites.h"
#include "test.h"

int t_failures = 0;
int t_checks = 0;
const char *t_current = "";

const char *t_tmpdir(void)
{
    static char path[RS_PATH_MAX];
    const char *base = getenv("TMPDIR");
    snprintf(path, sizeof path, "%s/romsync-3ds-XXXXXX", base && *base ? base : "/tmp");
    if (!mkdtemp(path)) {
        perror("mkdtemp");
        exit(2);
    }
    return path;
}

static int rm_entry(const char *path, const struct stat *st, int flag, struct FTW *ftw)
{
    (void)st;
    (void)flag;
    (void)ftw;
    return remove(path);
}

void t_rmtree(const char *path)
{
    nftw(path, rm_entry, 16, FTW_DEPTH | FTW_PHYS);
}

void t_write(const char *path, const void *data, size_t len)
{
    rs_error err;
    if (rs_write_file_atomic(path, data, len, &err) != RS_OK) {
        fprintf(stderr, "t_write: %s\n", err.message);
        exit(2);
    }
}

const char *t_repo(const char *relative)
{
    static char path[RS_PATH_MAX];
    rs_path_join(path, sizeof path, REPO_ROOT, relative);
    return path;
}

unsigned char *t_fake_rom(const char *title, const char *code, size_t size)
{
    unsigned char *b = calloc(1, size);
    for (size_t i = 0x200; i < size; i++)
        b[i] = (unsigned char)((i * 31) & 0xFF);
    memcpy(b, title, strlen(title));
    memcpy(b + 0x0C, code, 4);
    memcpy(b + 0x10, "01", 2);
    return b;
}

int main(void)
{
    run_hash_tests();
    run_nds_tests();
    run_profile_tests();
    printf("%d checks, %d failures\n", t_checks, t_failures);
    return t_failures ? 1 : 0;
}
