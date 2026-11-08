/* platform_linux.c - rs_platform_* for the Linux tests (see core/platform.h). */
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

#include "../core/platform.h"

void rs_platform_random(void *buf, size_t n)
{
    FILE *f = fopen("/dev/urandom", "rb");
    if (!f || fread(buf, 1, n, f) != n) {
        perror("/dev/urandom");
        exit(2);
    }
    fclose(f);
}

rs_time rs_platform_now(void)
{
    return (rs_time)time(NULL);
}
