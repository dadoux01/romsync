/*
 * ui.c - text interface on the two screens (see ui.h).
 */
#include "ui.h"

#include <3ds.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>

#include "../core/cp437.h"
#include "text.h"

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

void ui_print(const char *fmt, ...)
{
    char utf8[1024], cp[1024];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(utf8, sizeof utf8, fmt, ap);
    va_end(ap);
    rs_to_cp437(utf8, cp, sizeof cp, 0);
    fputs(cp, stdout);
}

/* Number of characters (not bytes) of UTF-8 text. */
static int utf8_len(const char *s)
{
    int n = 0;
    while (*s) {
        rs_utf8_next(&s);
        n++;
    }
    return n;
}

void ui_print_fit(const char *text, int width)
{
    char cp[512];
    rs_to_cp437(text, cp, sizeof cp, width);
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
            rs_utf8_next(&p);
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
        /* At the bottom, raised by its extra lines. */
        int lines = 0;
        for (const char *c = footer; *c; c++)
            lines += *c == '\n';
        ui_move(UI_ROWS - 2 - lines, 0);
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
    dialog(title, text, RS_TR(OK_KEY));
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

char ui_choose(const char *title, const char *text, const char *a, const char *y, const char *b)
{
    char footer[120];
    snprintf(footer, sizeof footer, "A : %s\nY : %s\nB : %s", a, y, b);
    dialog(title, text, footer);
    while (aptMainLoop()) {
        hidScanInput();
        u32 k = hidKeysDown();
        if (k & KEY_A)
            return 'A';
        if (k & KEY_Y)
            return 'Y';
        if (k & KEY_B)
            return 'B';
        ui_frame();
    }
    return 'B';
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
    swkbdSetButton(&kb, SWKBD_BUTTON_LEFT, RS_TR(CANCEL), false);
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
