/*
 * profile.h - conversion profiles (the profiles/ JSON files, docs/SPEC.md, "Format
 * canonique et conversion"), shared with the Flutter client.
 *
 * decode() only removes what an emulator adds around the save (a footer);
 * it never cuts the save itself: size rules are the server's job.
 */
#ifndef RS_PROFILE_H
#define RS_PROFILE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "rs.h"

#define RS_PROFILE_MAX_FIELDS 8
#define RS_MAX_PROFILES 16

/* Value of a footer field: a fixed number, or computed from the save. */
typedef enum {
    RS_FIELD_NUMBER,
    RS_FIELD_RAW_SIZE,          /* size of the raw save */
    RS_FIELD_DESMUME_SAVE_TYPE, /* index in DeSmuME's save_types table */
    RS_FIELD_DESMUME_ADDR_SIZE, /* 1, 2 or 3 bytes of address */
} rs_field_kind;

typedef struct {
    char name[32];
    rs_field_kind kind;
    uint32_t number; /* RS_FIELD_NUMBER only */
} rs_profile_field;

typedef struct {
    char id[32];
    char name[64];
    char status[16];    /* "confirmed" or "to_verify" */
    char extension[16]; /* with its dot, e.g. ".sav" */

    bool has_footer;
    size_t footer_length;
    char *footer_prefix; /* malloc'ed, may be "" */
    char *footer_cookie; /* malloc'ed, may be "" */
    rs_profile_field fields[RS_PROFILE_MAX_FIELDS];
    int field_count;

    bool pad_min;     /* size.output: false = "exact", true = "pad_min" */
    size_t pad_to;    /* pad_min: minimum size */
    uint8_t pad_byte; /* pad_min: filler byte */
} rs_profile;

typedef struct {
    rs_profile items[RS_MAX_PROFILES];
    int count;
} rs_profiles;

/* Parses one profile document. */
rs_status rs_profile_parse(const char *json, rs_profile *out, rs_error *err);
void rs_profile_free(rs_profile *p);

/* Turns a file of this profile into raw save data (out is replaced). */
rs_status rs_profile_decode(const rs_profile *p, const uint8_t *file, size_t len, rs_buf *out,
                            rs_error *err);
/* Turns raw save data into a file of this profile. chip_size is the game's
 * chip size, used by pad_min profiles (0 when unknown). */
rs_status rs_profile_encode(const rs_profile *p, const uint8_t *raw, size_t len, size_t chip_size,
                            rs_buf *out, rs_error *err);

/* Loads every JSON file of dir, sorted by name, into set (profiles
 * already in set with the same id are replaced). */
rs_status rs_profiles_load_dir(rs_profiles *set, const char *dir, rs_error *err);
const rs_profile *rs_profiles_find(const rs_profiles *set, const char *id);
void rs_profiles_free(rs_profiles *set);

#endif
