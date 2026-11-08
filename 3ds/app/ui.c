/*
 * ui.c - text interface on the two screens (see ui.h).
 */
#include "ui.h"

#include <3ds.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>

static PrintConsole top_console, bottom_console;

void ui_init(void)
{
    /* Two independent consoles, one per screen; consoleSelect() chooses
     * where printf writes. */
    gfxInitDefault();
    consoleInit(GFX_TOP, &top_console);
    consoleInit(GFX_BOTTOM, &bottom_console);
}

void ui_top(void)
{
    consoleSelect(&top_console);
}

void ui_bottom(void)
{
    consoleSelect(&bottom_console);
}

void ui_clear(void)
{
    consoleClear();
}

void ui_move(int row, int col)
{
    /* ANSI escape: rows and columns start at 1. */
    printf("\x1b[%d;%dH", row + 1, col + 1);
}

/* ---- UTF-8 to code page 437 -------------------------------------------- */

/* Reads one UTF-8 character at *s, advances *s, returns its code point. */
static unsigned utf8_next(const char **s)
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
static unsigned char cp437(unsigned c)
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
static void to_cp437(const char *in, char *out, size_t size, int max_cols)
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
            utf8_next(&in);
            continue;
        }
        unsigned c = utf8_next(&in);
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
        unsigned char g = cp437(c);
        out[k++] = g ? (char)g : '?';
        cols++;
    }
    out[k] = 0;
}

void ui_print(const char *fmt, ...)
{
    char utf8[1024], cp[1024];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(utf8, sizeof utf8, fmt, ap);
    va_end(ap);
    to_cp437(utf8, cp, sizeof cp, 0);
    fputs(cp, stdout);
}

/* Number of characters (not bytes) of UTF-8 text. */
static int utf8_len(const char *s)
{
    int n = 0;
    while (*s) {
        utf8_next(&s);
        n++;
    }
    return n;
}

void ui_print_fit(const char *text, int width)
{
    char cp[512];
    to_cp437(text, cp, sizeof cp, width);
    fputs(cp, stdout);
    for (int n = utf8_len(text); n < width; n++)
        putchar(' ');
}

void ui_print_wrapped(const char *text, int width)
{
    char line[256];
    while (*text) {
        /* Take as many words as fit in width characters. */
        const char *p = text, *cut = NULL;
        int n = 0;
        while (*p && *p != '\n' && n < width) {
            if (*p == ' ')
                cut = p;
            utf8_next(&p);
            n++;
        }
        if (!*p || *p == '\n' || !cut)
            cut = p;
        size_t len = (size_t)(cut - text);
        if (len >= sizeof line)
            len = sizeof line - 1;
        memcpy(line, text, len);
        line[len] = 0;
        ui_print("%s\n", line);
        text = cut;
        while (*text == ' ' || *text == '\n')
            text++;
    }
}

/* ---- Dialogs on the bottom screen -------------------------------------- */

static void dialog(const char *title, const char *text, const char *footer)
{
    ui_bottom();
    ui_clear();
    ui_print(UI_CYAN "%s" UI_RESET "\n\n", title);
    ui_print_wrapped(text, UI_BOTTOM_COLS);
    if (footer) {
        ui_move(UI_ROWS - 2, 0);
        ui_print("%s", footer);
    }
}

void ui_frame(void)
{
    gfxFlushBuffers();
    gfxSwapBuffers();
    gspWaitForVBlank();
}

void ui_message(const char *title, const char *text)
{
    dialog(title, text, "A : OK");
    while (aptMainLoop()) {
        hidScanInput();
        if (hidKeysDown() & (KEY_A | KEY_B))
            break;
        ui_frame();
    }
}

bool ui_confirm(const char *title, const char *text, const char *yes, const char *no)
{
    char footer[96];
    snprintf(footer, sizeof footer, "A : %s   B : %s", yes, no);
    dialog(title, text, footer);
    while (aptMainLoop()) {
        hidScanInput();
        u32 k = hidKeysDown();
        if (k & KEY_A)
            return true;
        if (k & KEY_B)
            return false;
        ui_frame();
    }
    return false;
}

void ui_progress(const char *title, const char *text)
{
    dialog(title, text, NULL);
    ui_frame();
}

/* ---- System keyboard --------------------------------------------------- */

bool ui_keyboard(const char *hint, char *text, size_t size, bool numbers_only)
{
    /* swkbd is a system applet: it takes over both screens until the user
     * confirms or cancels, then gives them back to the app. */
    SwkbdState kb;
    swkbdInit(&kb, numbers_only ? SWKBD_TYPE_NUMPAD : SWKBD_TYPE_WESTERN, 2, (int)size - 1);
    swkbdSetHintText(&kb, hint);
    swkbdSetInitialText(&kb, text);
    swkbdSetValidation(&kb, SWKBD_NOTEMPTY_NOTBLANK, 0, 0);
    swkbdSetButton(&kb, SWKBD_BUTTON_LEFT, "Annuler", false);
    swkbdSetButton(&kb, SWKBD_BUTTON_RIGHT, "OK", true);
    char buf[256];
    if (size > sizeof buf)
        size = sizeof buf;
    SwkbdButton pressed = swkbdInputText(&kb, buf, size);
    if (pressed != SWKBD_BUTTON_RIGHT)
        return false;
    snprintf(text, size, "%s", buf);
    return true;
}
