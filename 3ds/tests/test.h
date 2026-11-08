/*
 * test.h - a deliberately tiny test framework.
 *
 * Each test is a void function; CHECK* macros count failures and print
 * the file, line and test name, then the test goes on. main() (main.c)
 * runs every test with RUN() and exits with 1 when something failed.
 */
#ifndef RS_TEST_H
#define RS_TEST_H

#include <stdio.h>
#include <string.h>

extern int t_failures;
extern int t_checks;
extern const char *t_current;

#define CHECK(cond)                                                                            \
    do {                                                                                       \
        t_checks++;                                                                            \
        if (!(cond)) {                                                                         \
            t_failures++;                                                                      \
            fprintf(stderr, "%s:%d: [%s] CHECK(%s) failed\n", __FILE__, __LINE__, t_current,   \
                    #cond);                                                                    \
        }                                                                                      \
    } while (0)

#define CHECK_INT(a, b)                                                                        \
    do {                                                                                       \
        long long a_ = (long long)(a), b_ = (long long)(b);                                    \
        t_checks++;                                                                            \
        if (a_ != b_) {                                                                        \
            t_failures++;                                                                      \
            fprintf(stderr, "%s:%d: [%s] %s == %lld, expected %lld\n", __FILE__, __LINE__,     \
                    t_current, #a, a_, b_);                                                    \
        }                                                                                      \
    } while (0)

#define CHECK_STR(a, b)                                                                        \
    do {                                                                                       \
        const char *a_ = (a), *b_ = (b);                                                       \
        t_checks++;                                                                            \
        if (!a_ || !b_ || strcmp(a_, b_) != 0) {                                               \
            t_failures++;                                                                      \
            fprintf(stderr, "%s:%d: [%s] %s == \"%s\", expected \"%s\"\n", __FILE__, __LINE__, \
                    t_current, #a, a_ ? a_ : "(null)", b_ ? b_ : "(null)");                    \
        }                                                                                      \
    } while (0)

#define RUN(fn)                                                                                \
    do {                                                                                       \
        t_current = #fn;                                                                       \
        fn();                                                                                  \
    } while (0)

/* Helpers (main.c). */

/* Creates a fresh temporary folder; returns its path (static storage). */
const char *t_tmpdir(void);
/* Removes a folder and everything inside. */
void t_rmtree(const char *path);
/* Writes a file, creating its folders. */
void t_write(const char *path, const void *data, size_t len);
/* Path inside the repository (REPO_ROOT is set by the Makefile). */
const char *t_repo(const char *relative);
/* A fake ROM of size bytes with the given header fields (like
 * romsync_core's test/support/roms.dart). Returns a malloc'ed buffer. */
unsigned char *t_fake_rom(const char *title, const char *code, size_t size);

#endif
