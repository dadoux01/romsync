/*
 * cp437.c - UTF-8 to the console's code page (see cp437.h).
 */
#include "cp437.h"

/* Reads one UTF-8 character at *s, advances *s, returns its code point. */
unsigned rs_utf8_next(const char **s)
{
    const unsigned char *p = (const unsigned char *)*s;
    unsigned c = *p;
    int extra = c >= 0xF0 ? 3 : c >= 0xE0 ? 2 : c >= 0xC0 ? 1 : 0;
    if (extra)
        c &= 0x3F >> extra;
    p++;
    for (int i = 0; i < extra && (*p & 0xC0) == 0x80; i++)
        c = (c << 6) | (*p++ & 0x3F);
    *s = (const char *)p;
    return c;
}

/* CP437 code of a code point, or 0 when the font has no such glyph. */
unsigned char rs_cp437(unsigned c)
{
    if (c < 0x80)
        return (unsigned char)c;
    switch (c) {
    case 0xE9: return 0x82; /* é */
    case 0xE8: return 0x8A; /* è */
    case 0xEA: return 0x88; /* ê */
    case 0xEB: return 0x89; /* ë */
    case 0xE0: return 0x85; /* à */
    case 0xE2: return 0x83; /* â */
    case 0xE4: return 0x84; /* ä */
    case 0xE7: return 0x87; /* ç */
    case 0xEE: return 0x8C; /* î */
    case 0xEF: return 0x8B; /* ï */
    case 0xF4: return 0x93; /* ô */
    case 0xF6: return 0x94; /* ö */
    case 0xF9: return 0x97; /* ù */
    case 0xFB: return 0x96; /* û */
    case 0xFC: return 0x81; /* ü */
    case 0xC9: return 0x90; /* É */
    case 0xC7: return 0x80; /* Ç */
    case 0xAB: return 0xAE; /* « */
    case 0xBB: return 0xAF; /* » */
    case 0xA0: return ' ';  /* no-break space */
    case 0x2019: return '\''; /* ’ */
    case 0x2192: return 0x1A; /* → */
    }
    if (c == 0xC0 || c == 0xC2)
        return 'A';
    if (c == 0xC8 || c == 0xCA)
        return 'E';
    return 0;
}

/* Converts UTF-8 text to CP437, cut at max_cols characters when > 0.
 * ANSI escape sequences are copied as they are and take no column. */
void rs_to_cp437(const char *in, char *out, size_t size, int max_cols)
{
    size_t k = 0;
    int cols = 0;
    while (*in && k + 4 < size) {
        if (*in == '\x1b') {
            while (*in && k + 1 < size) {
                char ch = *in++;
                out[k++] = ch;
                if ((ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z'))
                    break;
            }
            continue;
        }
        if (*in == '\n')
            cols = -1;
        if (max_cols > 0 && cols >= max_cols && *in != '\n') {
            rs_utf8_next(&in);
            continue;
        }
        unsigned c = rs_utf8_next(&in);
        if (c == 0x2026) { /* … */
            out[k++] = '.';
            out[k++] = '.';
            out[k++] = '.';
            cols += 3;
            continue;
        }
        if (c == 0x153) { /* œ */
            out[k++] = 'o';
            out[k++] = 'e';
            cols += 2;
            continue;
        }
        unsigned char g = rs_cp437(c);
        out[k++] = g ? (char)g : '?';
        cols++;
    }
    out[k] = 0;
}
