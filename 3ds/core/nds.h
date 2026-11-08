/*
 * nds.h - Nintendo DS ROM header and game identifiers
 * (docs/SPEC.md, "Identification des jeux").
 */
#ifndef RS_NDS_H
#define RS_NDS_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "rs.h"

/* Number of header bytes needed to parse the fields below. */
#define RS_NDS_HEADER_LEN 0x20

/* Longest identifier: "h:" + 40 hex digits. */
#define RS_GAME_ID_MAX 48

typedef struct {
    char title[13];     /* 0x000, 12 bytes, trimmed */
    char game_code[5];  /* 0x00C, 4 ASCII bytes, e.g. "IRBF" */
    char maker_code[3]; /* 0x010, 2 bytes */
    uint8_t unit_code;  /* 0x012: 0 DS, 2 DS/DSi, 3 DSi only */
    uint8_t rom_version;/* 0x01E */
} rs_nds_header;

/* Parses the first bytes of a ROM; false when len < RS_NDS_HEADER_LEN. */
bool rs_nds_parse(const uint8_t *bytes, size_t len, rs_nds_header *out);

/* Whether the header carries a usable cartridge code. Homebrew usually has
 * "####" or zeros, which do not identify a game. */
bool rs_nds_has_valid_code(const rs_nds_header *h);

/* Whether id is accepted by the server: "IRBF", "h:<40 hex>" or
 * "x:<1 to 32 of a-z 0-9 ->". */
bool rs_game_id_valid(const char *id);

/* The forced identifier for a user-chosen name ("Platine Multi" ->
 * "x:platine-multi"); false when name cannot be made valid. */
bool rs_game_id_custom(const char *name, char *out, size_t size);

/* Reads only the header of a ROM file. */
rs_status rs_rom_identify_header(const char *path, rs_nds_header *header, rs_error *err);

/* Identifier of a ROM: its cartridge code, or "h:<sha1 of the ROM>".
 * Reads the ROM file; the SHA-1 is only computed for homebrew. */
rs_status rs_rom_identify(const char *path, rs_nds_header *header, char id[RS_GAME_ID_MAX],
                          rs_error *err);

#endif
