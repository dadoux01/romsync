/*
 * platform.h - the few things the core needs from the system, implemented
 * once per platform:
 *   - tests/platform_linux.c on Linux (/dev/urandom, time());
 *   - app/platform_3ds.c on the 3DS (libctru).
 * The core itself never includes a system-specific header.
 */
#ifndef RS_PLATFORM_H
#define RS_PLATFORM_H

#include <stddef.h>

#include "clock.h"

/* Fills buf with n random bytes (upload identifiers). */
void rs_platform_random(void *buf, size_t n);

/* Current time of the device clock, in seconds since 1970 (as the device
 * believes it: on the 3DS it is the console clock, without time zone). */
rs_time rs_platform_now(void);

#endif
