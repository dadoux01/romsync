/*
 * browser.h - a small folder browser of the SD card, to choose the ROM
 * folders (console text: folders, A enter, B back, X choose this folder).
 */
#ifndef RS_BROWSER_H
#define RS_BROWSER_H

#include <stdbool.h>
#include <stddef.h>

/* Lets the user pick a folder, starting at start ("sdmc:/" when empty).
 * Returns false when the user leaves with START. */
bool browse_folder(const char *start, char *out, size_t size);

#endif
