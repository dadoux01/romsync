/*
 * launch.h - starting a DS game from RomSync, through a YANBF forwarder.
 *
 * A 3DS-mode app cannot start a .nds file itself: the game must run in DSi
 * mode. YANBF (Yet Another nds-bootstrap Forwarder) solves this with a
 * DSi-mode title, "bootstrap.cia", that reads the ROM path from
 * sd:/_nds/ntr-forwarder/path.txt and starts it with the NTR forwarder
 * (sd:/_nds/ntr-forwarder/sdcard.nds), which runs nds-bootstrap. RomSync
 * writes path.txt and jumps to that title, exactly like YANBF's own
 * forwarders (YANBF, forwarder/source/main.c).
 *
 * This is optional: without bootstrap.cia, RomSync only syncs, and the
 * games are started from TWiLight Menu++.
 */
#ifndef RS_LAUNCH_H
#define RS_LAUNCH_H

#include <stdbool.h>
#include <stddef.h>

/* Title id of YANBF's bootstrap.cia (DSi-mode title on the NAND). */
#define YANBF_BOOTSTRAP_TID 0x0004800546574452ULL

/* Whether the game can be launched: bootstrap.cia installed, NTR forwarder
 * files on the SD card, and the same save file for the forwarder as for
 * TWiLight Menu++. Otherwise why explains what to install or change. */
bool launch_check(const char *rom_path, char *why, size_t size);

/* Writes path.txt and asks the system to jump to bootstrap.cia. On
 * success, the app must quit at once: the jump happens when it exits. */
bool launch_start(const char *rom_path, char *why, size_t size);

#endif
