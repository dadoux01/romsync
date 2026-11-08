/*
 * updater.c - see updater.h.
 */
#include "updater.h"

#include <3ds.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../core/update.h"
#include "ui.h"

void app_check_compatibility(app *a)
{
    static bool checked;
    if (checked || !a->online)
        return;
    rs_server_info info;
    bool exists;
    if (rs_api_server(&a->api, &info, &exists, NULL) != RS_OK)
        return; /* checked again at the next start */
    checked = true;
    char text[400];
    switch (rs_check_compatibility(exists ? &info : NULL, RS_VERSION)) {
    case RS_COMPAT_SERVER_TOO_OLD:
        snprintf(text, sizeof text,
                 "Le serveur RomSync (%s) est trop ancien pour cette version de RomSync (%s).\n\n"
                 "Mets d'abord à jour le serveur (nouvelle image Docker). En attendant, le choix en cas de "
                 "divergence n'est pas disponible.",
                 exists ? info.version : "antérieur à 0.5.0", RS_VERSION);
        ui_message("Serveur trop ancien", text);
        break;
    case RS_COMPAT_CLIENT_TOO_OLD:
        snprintf(text, sizeof text,
                 "Cette version de RomSync (%s) est trop ancienne pour le serveur, qui demande au moins la %s : "
                 "mets-la à jour (SELECT, puis « Rechercher une mise à jour »).",
                 RS_VERSION, info.min_client_version);
        ui_message("RomSync trop ancien", text);
        break;
    case RS_COMPAT_OK:
        break;
    }
}

/* Installs a CIA from memory with the AM service (application manager),
 * as Universal-Updater does. */
static Result install_cia(const uint8_t *data, size_t len)
{
    Result rc = amInit();
    if (R_FAILED(rc))
        return rc;
    Handle h;
    rc = AM_StartCiaInstall(MEDIATYPE_SD, &h);
    if (R_SUCCEEDED(rc)) {
        const size_t chunk = 64 * 1024;
        for (size_t off = 0; off < len && R_SUCCEEDED(rc); off += chunk) {
            u32 written = 0;
            u32 n = (u32)(len - off < chunk ? len - off : chunk);
            rc = FSFILE_Write(h, &written, off, data + off, n, 0);
            if (R_SUCCEEDED(rc) && written != n)
                rc = -1;
            char text[64];
            snprintf(text, sizeof text, "Installation...\n\n%u / %u Kio", (unsigned)((off + n) / 1024),
                     (unsigned)(len / 1024));
            ui_progress("Mise à jour", text);
        }
        if (R_SUCCEEDED(rc))
            rc = AM_FinishCiaInstall(h);
        else
            AM_CancelCIAInstall(h);
    }
    amExit();
    return rc;
}

/* Release notes shortened for the bottom screen. */
static void short_notes(const char *notes, char *out, size_t size)
{
    size_t k = 0;
    for (const char *p = notes ? notes : ""; *p && k + 4 < size; p++) {
        if (*p == '#' || *p == '*' || *p == '`' || *p == '\r')
            continue; /* Markdown marks */
        out[k++] = *p;
    }
    out[k] = 0;
    if (notes && strlen(notes) >= size - 4)
        rs_strlcpy(out + k, "...", size - k);
}

bool app_check_update(app *a, bool manual)
{
    rs_release_version me;
    if (!rs_version_parse(RS_VERSION, &me)) {
        if (manual)
            ui_message("Mise à jour", "Version de développement : pas de mise à jour automatique.");
        return false;
    }
    if (!a->online) {
        if (manual)
            ui_message("Mise à jour", "Serveur injoignable : réessaie quand la console est connectée.");
        return false;
    }
    ui_progress("Mise à jour", "Recherche d'une nouvelle version...");
    rs_update_info u;
    bool exists = false;
    rs_error err = {0};
    if (rs_api_platform_update(&a->api, "3ds", &u, &exists, &err) != RS_OK || !exists ||
        !rs_is_update(u.version, RS_VERSION)) {
        if (manual)
            ui_message("Mise à jour",
                       err.message[0] ? err.message
                       : exists        ? "RomSync est à jour."
                                       : "Le serveur ne propose pas de mise à jour (relais désactivé, serveur trop "
                                         "ancien ou aucune version publiée).");
        rs_update_info_free(&u);
        return false;
    }

    char notes[700], text[900];
    short_notes(u.notes, notes, sizeof notes);
    snprintf(text, sizeof text, "Version actuelle : %s\n\n%s", RS_VERSION, notes);
    char title[64];
    snprintf(title, sizeof title, "RomSync %s est disponible", u.version);
    bool installed = false;
    if (!ui_confirm(title, text, "télécharger", "plus tard"))
        goto out;

    /* Download the three files, then check them before anything else. */
    rs_buf sums = {0}, sig = {0}, cia = {0};
    ui_progress("Mise à jour", "Téléchargement...");
    rs_status st = rs_api_get_file(&a->api, u.sums.url, &sums, &err);
    if (st == RS_OK)
        st = rs_api_get_file(&a->api, u.signature.url, &sig, &err);
    if (st == RS_OK)
        st = rs_api_get_file(&a->api, u.file.url, &cia, &err);
    if (st == RS_OK && !rs_buf_terminate(&sig))
        st = rs_fail(&err, RS_ERR_NOMEM, "Mémoire insuffisante");
    if (st == RS_OK) {
        ui_progress("Mise à jour", "Vérification de la signature...");
        st = rs_verify_release(sums.data, sums.len, (const char *)sig.data, u.file.name, cia.data, cia.len,
                               RS_RELEASE_PUBLIC_KEY, &err);
    }
    if (st != RS_OK) {
        ui_message("Mise à jour refusée", err.message);
    } else {
        snprintf(text, sizeof text,
                 "RomSync %s est téléchargée et vérifiée.\n\nL'installer maintenant ? RomSync se fermera ensuite : "
                 "relance-le depuis le menu HOME.",
                 u.version);
        if (ui_confirm("Installer", text, "installer", "annuler")) {
            Result rc = install_cia(cia.data, cia.len);
            if (R_SUCCEEDED(rc)) {
                installed = true;
                snprintf(text, sizeof text,
                         "RomSync %s est installée. RomSync va se fermer : relance-le depuis le menu HOME.",
                         u.version);
                ui_message("Mise à jour installée", text);
            } else {
                snprintf(text, sizeof text,
                         "L'installation a échoué (erreur 0x%08lX). La version actuelle reste en place.\n\nDepuis le "
                         "Homebrew Launcher, installe plutôt RomSync en .cia avec FBI.",
                         (unsigned long)rc);
                ui_message("Mise à jour", text);
            }
        }
    }
    rs_buf_free(&sums);
    rs_buf_free(&sig);
    rs_buf_free(&cia);
out:
    rs_update_info_free(&u);
    return installed;
}
