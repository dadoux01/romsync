/*
 * clock.h - dates and the console clock correction.
 *
 * Dates are seconds since 1970-01-01 UTC (rs_time). The 3DS clock is often
 * wrong (and has no time zone), so RomSync measures the gap between the
 * console and the server's "Date" header, and corrects the dates it sends
 * (X-Saved-At) with it. See 3ds/README.md, "Dates".
 */
#ifndef RS_CLOCK_H
#define RS_CLOCK_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef int64_t rs_time;

/* "2026-11-08T12:00:00Z" (needs 21 bytes; use 32). */
void rs_time_format_iso(rs_time t, char *out, size_t size);
/* Parses ISO 8601 / RFC 3339 dates as sent by the server:
 * "2026-11-08T12:00:00Z", with optional fractions and "+01:00" offsets. */
bool rs_time_parse_iso(const char *s, rs_time *out);
/* Parses an HTTP date: "Sun, 08 Nov 2026 12:00:00 GMT". */
bool rs_time_parse_http(const char *s, rs_time *out);

/* Gap between the server and the console clock. */
typedef struct {
    bool known;     /* false until the server answered once */
    int64_t offset; /* server time - console time, in seconds */
} rs_clock;

/* Records the gap seen on a response: the server said server_time while
 * the console read console_time. */
void rs_clock_observe(rs_clock *c, rs_time server_time, rs_time console_time);
/* The console time corrected by the last known gap (unchanged when the gap
 * was never measured). */
rs_time rs_clock_correct(const rs_clock *c, rs_time console_time);

#endif
