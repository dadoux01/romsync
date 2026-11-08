/*
 * test_library.c - TWiLight Menu++ settings, ROM scan and library entries,
 * on a fake SD card in a temporary folder.
 */
#include <stdlib.h>
#include <string.h>

#include "../core/library.h"
#include "../core/twilight.h"
#include "suites.h"
#include "test.h"

static char sd[RS_PATH_MAX];

static void sd_write(const char *rel, const char *text)
{
    char path[RS_PATH_MAX];
    rs_path_join(path, sizeof path, sd, rel);
    t_write(path, text, strlen(text));
}

static void sd_rom(const char *rel, const char *code)
{
    char path[RS_PATH_MAX];
    rs_path_join(path, sizeof path, sd, rel);
    unsigned char *rom = t_fake_rom("GAME", code, 4096);
    t_write(path, rom, 4096);
    free(rom);
}

/* Returns one of 4 rotating buffers: copy a path that must outlive the
 * next calls. */
static const char *sd_path(const char *rel)
{
    static char path[4][RS_PATH_MAX];
    static int next;
    char *out = path[next++ % 4];
    rs_path_join(out, RS_PATH_MAX, sd, rel);
    return out;
}

static void new_sd(void)
{
    rs_strlcpy(sd, t_tmpdir(), sizeof sd);
}

/* ---- INI and save paths ------------------------------------------------ */

static void reads_twilight_menu_ini_files(void)
{
    new_sd();
    sd_write("x.ini", "[SRLOADER]\r\nROM_FOLDER = sd:/roms/nds\r\nSAVE_LOCATION = 2\r\n\r\n[OTHER]\r\nSAVE_LOCATION = 1\r\n");
    char v[64];
    CHECK(rs_ini_get(sd_path("x.ini"), "SRLOADER", "ROM_FOLDER", v, sizeof v));
    CHECK_STR(v, "sd:/roms/nds");
    CHECK_INT(rs_ini_get_int(sd_path("x.ini"), "SRLOADER", "SAVE_LOCATION", 0), 2);
    CHECK_INT(rs_ini_get_int(sd_path("x.ini"), "OTHER", "SAVE_LOCATION", 0), 1);
    CHECK_INT(rs_ini_get_int(sd_path("x.ini"), "SRLOADER", "MISSING", 7), 7);
    CHECK(!rs_ini_get(sd_path("none.ini"), "SRLOADER", "ROM_FOLDER", v, sizeof v));
    t_rmtree(sd);
}

static void save_path_follows_save_location_and_slot(void)
{
    new_sd();
    char rom[RS_PATH_MAX], out[RS_PATH_MAX];
    rs_strlcpy(rom, sd_path("roms/nds/Pokemon Black.nds"), sizeof rom);

    /* No settings: default "saves" folder next to the ROM. */
    rs_twl_save_path(sd, RS_LAUNCHER_TWILIGHT, rom, out, sizeof out);
    CHECK_STR(out, sd_path("roms/nds/saves/Pokemon Black.sav"));

    sd_write("_nds/TWiLightMenu/settings.ini", "[SRLOADER]\nSAVE_LOCATION = 1\n");
    rs_twl_save_path(sd, RS_LAUNCHER_TWILIGHT, rom, out, sizeof out);
    CHECK_STR(out, sd_path("roms/nds/Pokemon Black.sav"));

    sd_write("_nds/TWiLightMenu/settings.ini", "[SRLOADER]\nSAVE_LOCATION = 2\n");
    rs_twl_save_path(sd, RS_LAUNCHER_TWILIGHT, rom, out, sizeof out);
    CHECK_STR(out, sd_path("_nds/TWiLightMenu/saves/Pokemon Black.sav"));

    /* Per-game save slot. */
    sd_write("_nds/TWiLightMenu/settings.ini", "[SRLOADER]\nSAVE_LOCATION = 0\n");
    sd_write("_nds/TWiLightMenu/gamesettings/Pokemon Black.nds.ini", "[GAMESETTINGS]\nSAVE_NUMBER = 3\n");
    CHECK_INT(rs_twl_save_slot(sd, RS_LAUNCHER_TWILIGHT, rom), 3);
    rs_twl_save_path(sd, RS_LAUNCHER_TWILIGHT, rom, out, sizeof out);
    CHECK_STR(out, sd_path("roms/nds/saves/Pokemon Black.sav3"));

    /* Next to the ROM, TWiLight Menu++ ignores the slot. */
    sd_write("_nds/TWiLightMenu/settings.ini", "[SRLOADER]\nSAVE_LOCATION = 1\n");
    rs_twl_save_path(sd, RS_LAUNCHER_TWILIGHT, rom, out, sizeof out);
    CHECK_STR(out, sd_path("roms/nds/Pokemon Black.sav"));
    t_rmtree(sd);
}

static void converts_paths_for_ds_mode_programs(void)
{
    char out[RS_PATH_MAX];
    rs_twl_ds_path("sdmc:/", "sdmc:/roms/nds/Game.nds", out, sizeof out);
    CHECK_STR(out, "sd:/roms/nds/Game.nds");
    rs_twl_ds_path("/tmp/sd", "/tmp/sd/roms/Game.nds", out, sizeof out);
    CHECK_STR(out, "sd:/roms/Game.nds");
}

static void detects_forwarder_settings_that_disagree(void)
{
    new_sd();
    char rom[RS_PATH_MAX], why[512];
    rs_strlcpy(rom, sd_path("roms/nds/Game.nds"), sizeof rom);
    rs_forwarder_mismatch(sd, rom, why, sizeof why);
    CHECK_STR(why, ""); /* both default to the saves folder */

    sd_write("_nds/TWiLightMenu/settings.ini", "[SRLOADER]\nSAVE_LOCATION = 1\n");
    rs_forwarder_mismatch(sd, rom, why, sizeof why);
    CHECK(strstr(why, "SAVE_LOCATION=1") != NULL);
    CHECK(strstr(why, "ntr_forwarder.ini") != NULL);

    sd_write("_nds/ntr_forwarder.ini", "[NTR-FORWARDER]\nSAVE_LOCATION = 1\n");
    rs_forwarder_mismatch(sd, rom, why, sizeof why);
    CHECK_STR(why, "");

    /* Same location, different save slot for the game. */
    sd_write("_nds/TWiLightMenu/settings.ini", "[SRLOADER]\nSAVE_LOCATION = 0\n");
    sd_write("_nds/ntr_forwarder.ini", "[NTR-FORWARDER]\nSAVE_LOCATION = 0\n");
    sd_write("_nds/ntr-forwarder/gamesettings/Game.nds.ini", "[GAMESETTINGS]\nSAVE_NUMBER = 2\n");
    rs_forwarder_mismatch(sd, rom, why, sizeof why);
    CHECK(strstr(why, "Emplacement de save différent") != NULL);
    t_rmtree(sd);
}

/* ---- Scan -------------------------------------------------------------- */

static void scans_folders_with_or_without_sub_folders(void)
{
    new_sd();
    sd_rom("roms/nds/Black.nds", "IRBF");
    sd_rom("roms/nds/rpg/Platinum.NDS", "CPUF");
    sd_rom("roms/nds/.hidden/Old.nds", "AAAA");
    sd_rom("roms/nds/saves/NotARom.nds", "BBBB");
    sd_write("roms/nds/notes.txt", "x");
    sd_write("roms/empty/readme.txt", "x");

    rs_config c;
    rs_config_load(&c, sd_path("3ds/romsync/config.json"), NULL);
    rs_config_add_folder(&c, sd_path("roms/nds"), false);
    rs_config_add_folder(&c, sd_path("roms/empty"), true);
    rs_scan_result r;
    rs_scan(&c, &r);
    CHECK_INT(r.count, 1);
    CHECK_INT(r.per_folder[0], 1);
    CHECK_INT(r.per_folder[1], 0); /* the app says "no ROM in this folder" */
    rs_scan_free(&r);

    c.folders[0].recursive = true;
    rs_scan(&c, &r);
    CHECK_INT(r.count, 2);
    CHECK_INT(r.per_folder[0], 2);
    bool black = false, platinum = false;
    for (int i = 0; i < r.count; i++) {
        black = black || strcmp(r.roms[i].detected_id, "IRBF") == 0;
        platinum = platinum || strcmp(r.roms[i].detected_id, "CPUF") == 0;
    }
    CHECK(black && platinum);
    rs_scan_free(&r);
    rs_config_free(&c);
    t_rmtree(sd);
}

static void homebrew_identifiers_are_cached_by_size(void)
{
    new_sd();
    sd_rom("roms/hb.nds", "####");
    rs_config c;
    rs_config_load(&c, sd_path("config.json"), NULL);
    rs_config_add_folder(&c, sd_path("roms"), true);
    rs_scan_result r;
    rs_scan(&c, &r);
    CHECK_INT(r.count, 1);
    CHECK(strncmp(r.roms[0].detected_id, "h:", 2) == 0);
    CHECK_STR(rs_config_cached_id(&c, sd_path("roms/hb.nds"), 4096), r.roms[0].detected_id);
    CHECK(rs_config_cached_id(&c, sd_path("roms/hb.nds"), 4097) == NULL);
    rs_scan_free(&r);
    rs_config_free(&c);
    t_rmtree(sd);
}

/* ---- Library ----------------------------------------------------------- */

static rs_profile twilight;

static void build(rs_config *c, rs_state_store *states, rs_library *lib)
{
    rs_scan_result r;
    rs_scan(c, &r);
    rs_build_library(&r, c, states, &twilight, sd, lib);
    rs_scan_free(&r);
}

static const rs_game *find(const rs_library *lib, const char *name)
{
    for (int i = 0; i < lib->count; i++)
        if (strcmp(rs_basename(lib->games[i].entry.rom_path), name) == 0)
            return &lib->games[i];
    return NULL;
}

static void roms_sharing_an_identifier_wait_for_a_choice_rom_by_rom(void)
{
    new_sd();
    sd_rom("roms/Platine.nds", "CPUF");
    sd_rom("roms/Platine-patch.nds", "CPUF");
    sd_rom("roms/Noire.nds", "IRBF");
    rs_config c;
    rs_config_load(&c, sd_path("config.json"), NULL);
    rs_config_add_folder(&c, sd_path("roms"), true);
    rs_state_store states = {0};
    rs_library lib;

    build(&c, &states, &lib);
    CHECK(find(&lib, "Platine.nds")->entry.needs_choice);
    CHECK(find(&lib, "Platine-patch.nds")->entry.needs_choice);
    CHECK(!find(&lib, "Noire.nds")->entry.needs_choice);
    CHECK_INT(find(&lib, "Platine.nds")->shared_count, 1);
    rs_library_free(&lib);

    /* One decision does not decide for the other ROM. */
    rs_config_set_choice(&c, sd_path("roms/Platine.nds"), true, NULL);
    build(&c, &states, &lib);
    CHECK(!find(&lib, "Platine.nds")->entry.needs_choice);
    CHECK(find(&lib, "Platine-patch.nds")->entry.needs_choice);
    rs_library_free(&lib);

    /* Separate: the forced x: identifier, which survives a reload. */
    char id[RS_GAME_ID_MAX];
    CHECK(rs_game_id_custom("platine patch", id, sizeof id));
    CHECK(rs_config_set_choice(&c, sd_path("roms/Platine-patch.nds"), false, id));
    CHECK(!rs_config_set_choice(&c, sd_path("roms/Platine-patch.nds"), false, "not valid"));
    CHECK_INT(rs_config_save(&c, NULL), RS_OK);
    rs_config_free(&c);
    rs_config_load(&c, sd_path("config.json"), NULL);
    build(&c, &states, &lib);
    CHECK_STR(find(&lib, "Platine.nds")->entry.game_id, "CPUF");
    CHECK_STR(find(&lib, "Platine-patch.nds")->entry.game_id, "x:platine-patch");
    CHECK(!find(&lib, "Platine-patch.nds")->entry.needs_choice);
    rs_library_free(&lib);
    rs_config_free(&c);
    t_rmtree(sd);
}

/* Only the active save slot is synced. A slot change is a change of save
 * file: an old file in the new slot is flagged, never sent blindly. */
static void a_save_slot_change_is_a_save_file_change(void)
{
    new_sd();
    sd_rom("roms/Game.nds", "IRBF");
    rs_config c;
    rs_config_load(&c, sd_path("config.json"), NULL);
    rs_config_add_folder(&c, sd_path("roms"), true);
    rs_state_store states;
    rs_state_open(&states, sd_path("state.json"), NULL);
    rs_library lib;

    build(&c, &states, &lib);
    const rs_game *g = find(&lib, "Game.nds");
    CHECK_INT(g->slot, 0);
    CHECK_STR(g->entry.save_path, sd_path("roms/saves/Game.sav"));
    CHECK(!g->stale_after_slot_change); /* no previous slot recorded */
    rs_config_set_slot(&c, g->entry.rom_path, g->slot);
    rs_state_record(&states, g->entry.save_path, "IRBF", 1, "h", 0, NULL);
    rs_library_free(&lib);

    /* The user picks slot 2 in TWiLight Menu++, where an old save lies. */
    sd_write("_nds/TWiLightMenu/gamesettings/Game.nds.ini", "[GAMESETTINGS]\nSAVE_NUMBER = 2\n");
    sd_write("roms/saves/Game.sav2", "old save");
    build(&c, &states, &lib);
    g = find(&lib, "Game.nds");
    CHECK_INT(g->slot, 2);
    CHECK_STR(g->entry.save_path, sd_path("roms/saves/Game.sav2"));
    CHECK(g->stale_after_slot_change);
    rs_library_free(&lib);

    /* Without a file in the new slot, nothing to warn about: the active
     * version will be downloaded into it. */
    remove(sd_path("roms/saves/Game.sav2"));
    build(&c, &states, &lib);
    CHECK(!find(&lib, "Game.nds")->stale_after_slot_change);
    rs_library_free(&lib);

    rs_state_close(&states);
    rs_config_free(&c);
    t_rmtree(sd);
}

static void config_round_trips(void)
{
    new_sd();
    rs_config c;
    CHECK_INT(rs_config_load(&c, sd_path("config.json"), NULL), RS_OK);
    CHECK_INT(c.keep_backups, 10);
    CHECK_STR(c.device_name, "3DS");
    rs_strlcpy(c.server_url, "http://192.168.1.68:8085", sizeof c.server_url);
    rs_config_add_folder(&c, "sdmc:/roms/nds", true);
    rs_config_add_folder(&c, "sdmc:/roms/hacks", false);
    rs_config_set_slot(&c, "sdmc:/roms/nds/a.nds", 3);
    CHECK_INT(rs_config_save(&c, NULL), RS_OK);
    rs_config_free(&c);

    CHECK_INT(rs_config_load(&c, sd_path("config.json"), NULL), RS_OK);
    CHECK_STR(c.server_url, "http://192.168.1.68:8085");
    CHECK_INT(c.folder_count, 2);
    CHECK(c.folders[0].recursive && !c.folders[1].recursive);
    CHECK_INT(rs_config_slot(&c, "sdmc:/roms/nds/a.nds"), 3);
    CHECK_INT(rs_config_slot(&c, "sdmc:/roms/nds/b.nds"), -1);
    rs_config_remove_folder(&c, 0);
    CHECK_INT(c.folder_count, 1);
    CHECK_STR(c.folders[0].path, "sdmc:/roms/hacks");
    rs_config_free(&c);
    t_rmtree(sd);
}

void run_library_tests(void)
{
    rs_profile_parse("{\"id\":\"twilight\",\"name\":\"TWiLight\",\"status\":\"to_verify\",\"extension\":\".sav\","
                     "\"size\":{\"output\":\"exact\"}}",
                     &twilight, NULL);
    RUN(reads_twilight_menu_ini_files);
    RUN(save_path_follows_save_location_and_slot);
    RUN(converts_paths_for_ds_mode_programs);
    RUN(detects_forwarder_settings_that_disagree);
    RUN(scans_folders_with_or_without_sub_folders);
    RUN(homebrew_identifiers_are_cached_by_size);
    RUN(roms_sharing_an_identifier_wait_for_a_choice_rom_by_rom);
    RUN(a_save_slot_change_is_a_save_file_change);
    RUN(config_round_trips);
    rs_profile_free(&twilight);
}
