/* test_nds.c - ROM header and identifiers, same cases as romsync_core's
 * rom_test.dart. */
#include <stdlib.h>
#include <string.h>

#include "../core/nds.h"
#include "../core/sha.h"
#include "suites.h"
#include "test.h"

static void parses_the_identification_fields(void)
{
    unsigned char *rom = t_fake_rom("POKEMON B", "IRBF", 4096);
    rom[0x12] = 2;
    rom[0x1E] = 1;
    rs_nds_header h;
    CHECK(rs_nds_parse(rom, 4096, &h));
    CHECK_STR(h.title, "POKEMON B");
    CHECK_STR(h.game_code, "IRBF");
    CHECK_STR(h.maker_code, "01");
    CHECK_INT(h.unit_code, 2);
    CHECK_INT(h.rom_version, 1);
    CHECK(rs_nds_has_valid_code(&h));
    free(rom);
}

static void homebrew_codes_are_not_valid(void)
{
    const char *codes[] = {"####", "\0\0\0\0", "0000", "abcd"};
    for (int i = 0; i < 4; i++) {
        unsigned char *rom = t_fake_rom("HB", "XXXX", 64);
        memcpy(rom + 0x0C, codes[i], 4);
        rs_nds_header h;
        rs_nds_parse(rom, 64, &h);
        CHECK(!rs_nds_has_valid_code(&h));
        free(rom);
    }
}

static void needs_32_bytes(void)
{
    unsigned char b[31] = {0};
    rs_nds_header h;
    CHECK(!rs_nds_parse(b, sizeof b, &h));
}

static void validates_like_the_server(void)
{
    char h40[64] = "h:", H40[64] = "h:", x33[64] = "x:";
    memset(h40 + 2, 'a', 40);
    memset(H40 + 2, 'A', 40);
    memset(x33 + 2, 'a', 33);
    const char *ok[] = {"IRBF", h40, "x:my-hack", "x:a"};
    for (int i = 0; i < 4; i++)
        CHECK(rs_game_id_valid(ok[i]));
    const char *bad[] = {"irbf", "IRB", H40, "x:My_Hack", "x:", x33, "y:abc"};
    for (int i = 0; i < 7; i++)
        CHECK(!rs_game_id_valid(bad[i]));
}

static void builds_custom_identifiers(void)
{
    char id[64];
    CHECK(rs_game_id_custom("Platine Multi", id, sizeof id));
    CHECK_STR(id, "x:platine-multi");
    CHECK(rs_game_id_custom("  my__hack  v2 ", id, sizeof id));
    CHECK_STR(id, "x:my-hack-v2");
    CHECK(!rs_game_id_custom("Pokémon", id, sizeof id));
    CHECK(!rs_game_id_custom("", id, sizeof id));
}

static void identifies_plain_roms_and_homebrew_by_sha1(void)
{
    const char *dir = t_tmpdir();
    char path[512], id[RS_GAME_ID_MAX];
    rs_nds_header h;

    unsigned char *rom = t_fake_rom("POKEMON B", "IRBF", 4096);
    snprintf(path, sizeof path, "%s/Black.nds", dir);
    t_write(path, rom, 4096);
    CHECK_INT(rs_rom_identify(path, &h, id, NULL), RS_OK);
    CHECK_STR(id, "IRBF");
    CHECK_STR(h.title, "POKEMON B");
    free(rom);

    /* Larger than the 16 KiB read buffer, to hash several chunks. */
    size_t size = 100000;
    unsigned char *hb = t_fake_rom("HOMEBREW", "####", size);
    snprintf(path, sizeof path, "%s/hb.nds", dir);
    t_write(path, hb, size);
    char sha1[41], expected[64];
    rs_sha1_hex(hb, size, sha1);
    snprintf(expected, sizeof expected, "h:%s", sha1);
    CHECK_INT(rs_rom_identify(path, &h, id, NULL), RS_OK);
    CHECK_STR(id, expected);
    free(hb);

    t_rmtree(dir);
}

void run_nds_tests(void)
{
    RUN(parses_the_identification_fields);
    RUN(homebrew_codes_are_not_valid);
    RUN(needs_32_bytes);
    RUN(validates_like_the_server);
    RUN(builds_custom_identifiers);
    RUN(identifies_plain_roms_and_homebrew_by_sha1);
}
