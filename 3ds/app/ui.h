/*
 * ui.h - text interface on the two screens, with libctru's console.
 *
 * The 3DS console prints an 8x8 font: the top screen holds 50 columns x 30
 * lines, the bottom screen 40 x 30. The font follows code page 437 (the
 * old IBM PC one), not UTF-8, so every string goes through ui_print, which
 * turns the French accents into their CP437 codes.
 */
#ifndef RS_UI_H
#define RS_UI_H

#include <stdbool.h>
#include <stddef.h>

#define UI_TOP_COLS 50
#define UI_BOTTOM_COLS 40
#define UI_ROWS 30

/* ANSI colours understood by the console. */
#define UI_RESET "\x1b[0m"
#define UI_RED "\x1b[31m"
#define UI_GREEN "\x1b[32m"
#define UI_YELLOW "\x1b[33m"
#define UI_BLUE "\x1b[34m"
#define UI_CYAN "\x1b[36m"
#define UI_WHITE "\x1b[37m"
#define UI_INVERSE "\x1b[7m"

void ui_init(void);
void ui_top(void);    /* following prints go to the top screen */
void ui_bottom(void); /* ... or to the bottom screen */
void ui_clear(void);  /* clears the selected screen */
/* Moves the cursor of the selected screen (row and column from 0). */
void ui_move(int row, int col);

/* printf for UTF-8 text: accents become CP437 codes, unknown characters
 * become '?'. */
void ui_print(const char *fmt, ...)
#if defined(__GNUC__)
    __attribute__((format(printf, 1, 2)))
#endif
    ;
/* Prints text cut (or padded with spaces) to exactly width columns. */
void ui_print_fit(const char *text, int width);
/* Prints text over several lines, cut at width columns between words. */
void ui_print_wrapped(const char *text, int width);

/* Shows a message on the bottom screen and waits for A (or B). */
void ui_message(const char *title, const char *text);
/* Asks a question on the bottom screen: returns true for A, false for B. */
bool ui_confirm(const char *title, const char *text, const char *yes, const char *no);
/* Asks a question with three answers: returns 'A', 'Y' or 'B'. */
char ui_choose(const char *title, const char *text, const char *a, const char *y, const char *b);
/* Shows "Patiente..." style progress on the bottom screen, without waiting. */
void ui_progress(const char *title, const char *text);
/* Refreshes the screens (swaps the buffers) and waits for the next frame. */
void ui_frame(void);

/* Opens the system keyboard. Returns false when the user cancels. text is
 * both the initial value and the result. */
bool ui_keyboard(const char *hint, char *text, size_t size, bool numbers_only);

#endif
