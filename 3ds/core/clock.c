/*
 * clock.c - dates and the console clock correction (see clock.h).
 *
 * newlib has no timegm(), so dates are converted with Howard Hinnant's
 * days_from_civil / civil_from_days algorithms (public domain), which only
 * use integer arithmetic.
 */
#include "clock.h"

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Days since 1970-01-01 of a proleptic Gregorian date. */
static int64_t days_from_civil(int64_t y, int m, int d)
{
    y -= m <= 2;
    int64_t era = (y >= 0 ? y : y - 399) / 400;
    int64_t yoe = y - era * 400;
    int64_t doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1;
    int64_t doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    return era * 146097 + doe - 719468;
}

static void civil_from_days(int64_t z, int64_t *y, int *m, int *d)
{
    z += 719468;
    int64_t era = (z >= 0 ? z : z - 146096) / 146097;
    int64_t doe = z - era * 146097;
    int64_t yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    int64_t doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    int64_t mp = (5 * doy + 2) / 153;
    *d = (int)(doy - (153 * mp + 2) / 5 + 1);
    *m = (int)(mp < 10 ? mp + 3 : mp - 9);
    *y = yoe + era * 400 + (*m <= 2);
}

static rs_time make_time(int64_t y, int mo, int d, int h, int mi, int s)
{
    return days_from_civil(y, mo, d) * 86400 + h * 3600 + mi * 60 + s;
}

void rs_time_format_iso(rs_time t, char *out, size_t size)
{
    int64_t days = t / 86400, rem = t % 86400;
    if (rem < 0) {
        rem += 86400;
        days--;
    }
    int64_t y;
    int m, d;
    civil_from_days(days, &y, &m, &d);
    snprintf(out, size, "%04lld-%02d-%02dT%02d:%02d:%02dZ", (long long)y, m, d, (int)(rem / 3600),
             (int)(rem / 60 % 60), (int)(rem % 60));
}

/* Reads exactly n digits. */
static bool digits(const char **p, int n, int *out)
{
    int v = 0;
    for (int i = 0; i < n; i++) {
        if (!isdigit((unsigned char)(*p)[i]))
            return false;
        v = v * 10 + ((*p)[i] - '0');
    }
    *p += n;
    *out = v;
    return true;
}

bool rs_time_parse_iso(const char *s, rs_time *out)
{
    int y, mo, d, h, mi, sec;
    const char *p = s;
    if (!digits(&p, 4, &y) || *p++ != '-' || !digits(&p, 2, &mo) || *p++ != '-' || !digits(&p, 2, &d))
        return false;
    if (*p != 'T' && *p != 't' && *p != ' ')
        return false;
    p++;
    if (!digits(&p, 2, &h) || *p++ != ':' || !digits(&p, 2, &mi) || *p++ != ':' || !digits(&p, 2, &sec))
        return false;
    if (*p == '.') /* fractions of a second are dropped */
        for (p++; isdigit((unsigned char)*p); p++)
            ;
    int offset = 0;
    if (*p == 'Z' || *p == 'z') {
        p++;
    } else if (*p == '+' || *p == '-') {
        int sign = *p++ == '-' ? -1 : 1, oh, om;
        if (!digits(&p, 2, &oh) || *p++ != ':' || !digits(&p, 2, &om))
            return false;
        offset = sign * (oh * 3600 + om * 60);
    } else {
        return false;
    }
    if (*p || mo < 1 || mo > 12 || d < 1 || d > 31 || h > 23 || mi > 59 || sec > 60)
        return false;
    *out = make_time(y, mo, d, h, mi, sec) - offset;
    return true;
}

bool rs_time_parse_http(const char *s, rs_time *out)
{
    static const char *months[] = {"Jan", "Feb", "Mar", "Apr", "May", "Jun",
                                   "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"};
    char mon[4];
    int d, y, h, mi, sec;
    /* The day name before the comma is not needed. */
    const char *comma = strchr(s, ',');
    if (!comma || sscanf(comma + 1, " %d %3s %d %d:%d:%d GMT", &d, mon, &y, &h, &mi, &sec) != 6)
        return false;
    for (int m = 0; m < 12; m++)
        if (strcmp(mon, months[m]) == 0) {
            *out = make_time(y, m + 1, d, h, mi, sec);
            return true;
        }
    return false;
}

void rs_clock_observe(rs_clock *c, rs_time server_time, rs_time console_time)
{
    c->known = true;
    c->offset = server_time - console_time;
}

rs_time rs_clock_correct(const rs_clock *c, rs_time console_time)
{
    return c->known ? console_time + c->offset : console_time;
}
