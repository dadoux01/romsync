/*
 * cp437.h - UTF-8 text to code page 437, the font of the 3DS console
 * (libctru prints an 8x8 font of the old IBM PC). Portable, so that the
 * tests can check that every text of the app can be shown.
 */
#ifndef RS_CP437_H
#define RS_CP437_H

#include <stddef.h>

/* Reads one UTF-8 character at *s, advances *s, returns its code point. */
unsigned rs_utf8_next(const char **s);

/* CP437 code of a code point, or 0 when the font has no such glyph. */
unsigned char rs_cp437(unsigned c);

/* Converts UTF-8 text to CP437, cut at max_cols characters when > 0.
 * ANSI escape sequences are copied as they are and take no column; an
 * unknown character becomes '?'. */
void rs_to_cp437(const char *in, char *out, size_t size, int max_cols);

#endif
