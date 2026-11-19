/*
 * test_msg.c - the texts of the core and of the 3DS screens: both
 * languages, the same printf conversions, and only characters the console
 * can show (docs/SPEC.md, "Langues").
 */
#include <stdbool.h>
#include <stdio.h>
#include <string.h>

#include "../app/text.h"
#include "../core/config.h"
#include "../core/cp437.h"
#include "../core/msg.h"
#include "../core/sync.h"
#include "suites.h"
#include "test.h"

/* The printf conversions of fmt ("%s%d%zu..."), "%%" excluded. */
static void conversions(const char *fmt, char *out, size_t size)
{
    size_t k = 0;
    for (const char *p = fmt; *p && k + 1 < size; p++) {
        if (*p != '%')
            continue;
        p++;
        if (*p == '%')
            continue;
        while (*p && !strchr("sdiuxXlczp", *p) && k + 1 < size)
            out[k++] = *p++; /* flags, width, precision */
        while (*p && strchr("lz", *p) && k + 1 < size)
            out[k++] = *p++;
        if (*p && k + 1 < size)
            out[k++] = *p;
    }
    out[k] = 0;
}

/* Whether every character of text has a glyph in the console's font. */
static bool shows_on_console(const char *text)
{
    char cp[2048];
    rs_to_cp437(text, cp, sizeof cp, 0);
    int expected = 0, got = 0;
    for (const char *p = text; *p; p++)
        expected += *p == '?';
    for (const char *p = cp; *p; p++)
        got += *p == '?';
    return got == expected;
}

static void check_message(const char *id, const char *fr, const char *en)
{
    t_current = id;
    char cf[64], ce[64];
    conversions(fr, cf, sizeof cf);
    conversions(en, ce, sizeof ce);
    CHECK_STR(ce, cf);
    CHECK(fr[0] != 0 && en[0] != 0);
    CHECK(shows_on_console(fr));
    CHECK(shows_on_console(en));
}

static void every_text_has_both_languages(void)
{
#define CHECK_ONE(id) check_message(#id, RS_MSG_##id(RS_FR), RS_MSG_##id(RS_EN));
    RS_CORE_MESSAGES(CHECK_ONE)
    RS_APP_TEXTS(CHECK_ONE)
#undef CHECK_ONE
}

static void the_language_can_change(void)
{
    rs_lang before = rs_language();
    CHECK_INT(rs_lang_from_code("fr"), RS_LANG_FR);
    CHECK_INT(rs_lang_from_code("en"), RS_LANG_EN);
    CHECK_INT(rs_lang_from_code("de"), RS_LANG_EN);
    CHECK_INT(rs_lang_from_code(NULL), RS_LANG_EN);
    rs_set_language(RS_LANG_EN);
    CHECK_STR(rs_status_label(RS_STATUS_TO_UPLOAD), "to upload");
    rs_error err;
    rs_fail(&err, RS_ERR_REFUSED, RS_TR(UPDATE_NOT_LISTED), "x.cia");
    CHECK_STR(err.message, "x.cia is not listed in SHA256SUMS: update refused.");
    rs_set_language(RS_LANG_FR);
    CHECK_STR(rs_status_label(RS_STATUS_TO_UPLOAD), "à envoyer");
    rs_set_language(before);
}

static void the_console_shows_french_accents(void)
{
    char cp[64];
    rs_to_cp437("é à « » ’ …", cp, sizeof cp, 0);
    CHECK_STR(cp, "\x82 \x85 \xae \xaf ' ...");
    CHECK(!shows_on_console("—"));
}

static void the_language_is_saved_in_the_settings(void)
{
    const char *dir = t_tmpdir();
    char path[RS_PATH_MAX];
    rs_path_join(path, sizeof path, dir, "config.json");
    rs_config c;
    CHECK_INT(rs_config_load(&c, path, NULL), RS_OK);
    CHECK_STR(c.language, ""); /* follows the console */
    rs_strlcpy(c.language, "en", sizeof c.language);
    CHECK_INT(rs_config_save(&c, NULL), RS_OK);
    rs_config_free(&c);
    CHECK_INT(rs_config_load(&c, path, NULL), RS_OK);
    CHECK_STR(c.language, "en");
    rs_config_free(&c);
    t_rmtree(dir);
}

void run_msg_tests(void)
{
    RUN(every_text_has_both_languages);
    RUN(the_language_can_change);
    RUN(the_console_shows_french_accents);
    RUN(the_language_is_saved_in_the_settings);
}
