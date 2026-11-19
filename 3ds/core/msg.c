/*
 * msg.c - language of the texts (see msg.h).
 */
#include "msg.h"

#include <string.h>

static rs_lang current = RS_LANG_EN;

void rs_set_language(rs_lang lang)
{
    current = lang;
}

rs_lang rs_language(void)
{
    return current;
}

rs_lang rs_lang_from_code(const char *code)
{
    return code && strcmp(code, "fr") == 0 ? RS_LANG_FR : RS_LANG_EN;
}
