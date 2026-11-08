/*
 * twilight.c - TWiLight Menu++ and NTR forwarder settings (see twilight.h).
 */
#include "twilight.h"

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

/* ---- INI files --------------------------------------------------------- */

static char *trim(char *s)
{
    while (isspace((unsigned char)*s))
        s++;
    size_t n = strlen(s);
    while (n > 0 && isspace((unsigned char)s[n - 1]))
        s[--n] = 0;
    return s;
}

bool rs_ini_get(const char *path, const char *section, const char *key, char *out, size_t size)
{
    FILE *f = fopen(path, "r");
    if (!f)
        return false;
    char line[512];
    bool in_section = false, found = false;
    while (!found && fgets(line, sizeof line, f)) {
        char *s = trim(line);
        if (*s == '[') {
            char *end = strchr(s, ']');
            if (end)
                *end = 0;
            in_section = strcasecmp(s + 1, section) == 0;
            continue;
        }
        char *eq = strchr(s, '=');
        if (!in_section || !eq || *s == ';' || *s == '#')
            continue;
        *eq = 0;
        if (strcasecmp(trim(s), key) == 0) {
            rs_strlcpy(out, trim(eq + 1), size);
            found = true;
        }
    }
    fclose(f);
    return found;
}

int rs_ini_get_int(const char *path, const char *section, const char *key, int def)
{
    char v[32];
    if (!rs_ini_get(path, section, key, v, sizeof v))
        return def;
    char *end;
    long n = strtol(v, &end, 10);
    return end == v ? def : (int)n;
}

/* ---- Settings of each launcher ------------------------------------------ */

static void settings_file(const char *sd_root, rs_launcher which, char *out, size_t size)
{
    rs_path_join(out, size, sd_root,
                 which == RS_LAUNCHER_TWILIGHT ? "_nds/TWiLightMenu/settings.ini" : "_nds/ntr_forwarder.ini");
}

rs_save_location rs_twl_save_location(const char *sd_root, rs_launcher which)
{
    char path[RS_PATH_MAX];
    settings_file(sd_root, which, path, sizeof path);
    int v = rs_ini_get_int(path, which == RS_LAUNCHER_TWILIGHT ? "SRLOADER" : "NTR-FORWARDER", "SAVE_LOCATION", 0);
    return v == 1 ? RS_SAVE_NEXT_TO_ROM : v == 2 ? RS_SAVE_IN_TWLM_FOLDER : RS_SAVE_IN_SAVES_FOLDER;
}

int rs_twl_save_slot(const char *sd_root, rs_launcher which, const char *rom_path)
{
    char rel[RS_PATH_MAX], path[RS_PATH_MAX];
    snprintf(rel, sizeof rel, "%s/gamesettings/%s.ini",
             which == RS_LAUNCHER_TWILIGHT ? "_nds/TWiLightMenu" : "_nds/ntr-forwarder", rs_basename(rom_path));
    rs_path_join(path, sizeof path, sd_root, rel);
    int slot = rs_ini_get_int(path, "GAMESETTINGS", "SAVE_NUMBER", 0);
    return slot >= 0 && slot <= 9 ? slot : 0;
}

void rs_twl_save_path(const char *sd_root, rs_launcher which, const char *rom_path, char *out, size_t size)
{
    rs_save_location loc = rs_twl_save_location(sd_root, which);
    int slot = rs_twl_save_slot(sd_root, which, rom_path);
    /* TWiLight Menu++ ignores the slot when saves are next to the ROM
     * (getSavExtension); the forwarder does not. */
    if (which == RS_LAUNCHER_TWILIGHT && loc == RS_SAVE_NEXT_TO_ROM)
        slot = 0;

    /* ROM name with its last extension replaced: "Game.nds" -> "Game.sav". */
    char name[RS_PATH_MAX];
    rs_strlcpy(name, rs_basename(rom_path), sizeof name);
    char *dot = strrchr(name, '.');
    if (dot)
        *dot = 0;
    char ext[8] = ".sav";
    if (slot > 0)
        snprintf(ext, sizeof ext, ".sav%d", slot);
    size_t n = strlen(name);
    snprintf(name + n, sizeof name - n, "%s", ext);

    char dir[RS_PATH_MAX], folder[RS_PATH_MAX];
    rs_dirname(rom_path, dir, sizeof dir);
    if (loc == RS_SAVE_NEXT_TO_ROM)
        rs_strlcpy(folder, dir, sizeof folder);
    else if (loc == RS_SAVE_IN_TWLM_FOLDER)
        rs_path_join(folder, sizeof folder, sd_root, "_nds/TWiLightMenu/saves");
    else
        rs_path_join(folder, sizeof folder, dir, "saves");
    rs_path_join(out, size, folder, name);
}

bool rs_twl_installed(const char *sd_root)
{
    char path[RS_PATH_MAX];
    rs_path_join(path, sizeof path, sd_root, "_nds/TWiLightMenu");
    return rs_dir_exists(path);
}

void rs_twl_ds_path(const char *sd_root, const char *path, char *out, size_t size)
{
    size_t n = strlen(sd_root);
    while (n > 0 && sd_root[n - 1] == '/')
        n--;
    const char *rest = strncmp(path, sd_root, n) == 0 ? path + n : path;
    while (*rest == '/')
        rest++;
    snprintf(out, size, "sd:/%s", rest);
}

static const char *location_label(rs_save_location loc)
{
    switch (loc) {
    case RS_SAVE_NEXT_TO_ROM:
        return "à côté de la ROM";
    case RS_SAVE_IN_TWLM_FOLDER:
        return "dossier de TWiLight Menu++";
    default:
        return "dossier saves";
    }
}

void rs_forwarder_mismatch(const char *sd_root, const char *rom_path, char *why, size_t size)
{
    why[0] = 0;
    char twl[RS_PATH_MAX], fwd[RS_PATH_MAX];
    rs_twl_save_path(sd_root, RS_LAUNCHER_TWILIGHT, rom_path, twl, sizeof twl);
    rs_twl_save_path(sd_root, RS_LAUNCHER_FORWARDER, rom_path, fwd, sizeof fwd);
    if (strcmp(twl, fwd) == 0)
        return;
    rs_save_location lt = rs_twl_save_location(sd_root, RS_LAUNCHER_TWILIGHT);
    rs_save_location lf = rs_twl_save_location(sd_root, RS_LAUNCHER_FORWARDER);
    if (lt != lf) {
        snprintf(why, size,
                 "TWiLight Menu++ range les saves dans : %s ; le forwarder dans : %s. Mets le même emplacement : "
                 "SAVE_LOCATION=%d dans la section [NTR-FORWARDER] de sd:/_nds/ntr_forwarder.ini.",
                 location_label(lt), location_label(lf), (int)lt);
        return;
    }
    int st = rs_twl_save_slot(sd_root, RS_LAUNCHER_TWILIGHT, rom_path);
    int sf = rs_twl_save_slot(sd_root, RS_LAUNCHER_FORWARDER, rom_path);
    snprintf(why, size,
             "Emplacement de save différent pour ce jeu : %d dans TWiLight Menu++, %d dans le forwarder. "
             "Choisis le même numéro de save dans les réglages du jeu des deux côtés (forwarder : maintenir Y "
             "au lancement).",
             lt == RS_SAVE_NEXT_TO_ROM ? 0 : st, sf);
}
