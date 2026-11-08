/*
 * platform_3ds.c - rs_platform_* on the 3DS (see core/platform.h).
 */
#include <3ds.h>
#include <stdlib.h>
#include <time.h>

#include "../core/platform.h"

void rs_platform_random(void *buf, size_t n)
{
    /* The "ps:ps" service (process services) has a hardware random number
     * generator; psInit() is called once in main(). If it fails, fall back
     * on rand() seeded with the clock: upload ids only need to be unique. */
    if (R_FAILED(PS_GenerateRandomBytes(buf, n))) {
        unsigned char *b = buf;
        for (size_t i = 0; i < n; i++)
            b[i] = (unsigned char)rand();
    }
}

rs_time rs_platform_now(void)
{
    /* time() reads the console clock (osGetTime). The 3DS has no time zone:
     * the value is the local time set in the system settings, read as if it
     * were UTC. RomSync corrects it with the server's Date header. */
    return (rs_time)time(NULL);
}
