/*
 * updater.c - see updater.h.
 */
#include "updater.h"
#include "text.h"

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
        snprintf(text, sizeof text, RS_TR(SERVER_TOO_OLD_TEXT),
                 exists ? info.version : RS_TR(SERVER_OLDER), RS_VERSION);
        ui_message(RS_TR(SERVER_TOO_OLD), text);
        break;
    case RS_COMPAT_CLIENT_TOO_OLD:
        snprintf(text, sizeof text, RS_TR(APP_TOO_OLD_TEXT),
                 RS_VERSION, info.min_client_version);
        ui_message(RS_TR(APP_TOO_OLD), text);
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
            snprintf(text, sizeof text, RS_TR(INSTALLING_PROGRESS), (unsigned)((off + n) / 1024),
                     (unsigned)(len / 1024));
            ui_progress(RS_TR(UPDATE), text);
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
            ui_message(RS_TR(UPDATE), RS_TR(UPDATE_DEV));
        return false;
    }
    if (!a->online) {
        if (manual)
            ui_message(RS_TR(UPDATE), RS_TR(UPDATE_OFFLINE));
        return false;
    }
    ui_progress(RS_TR(UPDATE), RS_TR(UPDATE_LOOKING));
    rs_update_info u;
    bool exists = false;
    rs_error err = {0};
    if (rs_api_platform_update(&a->api, "3ds", &u, &exists, &err) != RS_OK || !exists ||
        !rs_is_update(u.version, RS_VERSION)) {
        if (manual)
            ui_message(RS_TR(UPDATE),
                       err.message[0] ? err.message
                       : exists        ? RS_TR(UPDATE_UP_TO_DATE)
                                       : RS_TR(UPDATE_NO_RELAY));
        rs_update_info_free(&u);
        return false;
    }

    char notes[700], text[900];
    short_notes(u.notes, notes, sizeof notes);
    snprintf(text, sizeof text, RS_TR(UPDATE_NOTES), RS_VERSION, notes);
    char title[64];
    snprintf(title, sizeof title, RS_TR(UPDATE_AVAILABLE), u.version);
    bool installed = false;
    if (!ui_confirm(title, text, RS_TR(DOWNLOAD_LOWER), RS_TR(LATER)))
        goto out;

    /* Download the three files, then check them before anything else. */
    rs_buf sums = {0}, sig = {0}, cia = {0};
    ui_progress(RS_TR(UPDATE), RS_TR(DOWNLOADING));
    rs_status st = rs_api_get_file(&a->api, u.sums.url, &sums, &err);
    if (st == RS_OK)
        st = rs_api_get_file(&a->api, u.signature.url, &sig, &err);
    if (st == RS_OK)
        st = rs_api_get_file(&a->api, u.file.url, &cia, &err);
    if (st == RS_OK && !rs_buf_terminate(&sig))
        st = rs_fail(&err, RS_ERR_NOMEM, RS_TR(NOMEM));
    if (st == RS_OK) {
        ui_progress(RS_TR(UPDATE), RS_TR(VERIFYING));
        st = rs_verify_release(sums.data, sums.len, (const char *)sig.data, u.file.name, cia.data, cia.len,
                               RS_RELEASE_PUBLIC_KEY, &err);
    }
    if (st != RS_OK) {
        ui_message(RS_TR(UPDATE_REFUSED), err.message);
    } else {
        snprintf(text, sizeof text, RS_TR(UPDATE_READY), u.version);
        if (ui_confirm(RS_TR(INSTALL), text, RS_TR(INSTALL_LOWER), RS_TR(CANCEL_LOWER))) {
            Result rc = install_cia(cia.data, cia.len);
            if (R_SUCCEEDED(rc)) {
                installed = true;
                snprintf(text, sizeof text, RS_TR(UPDATE_INSTALLED_TEXT), u.version);
                ui_message(RS_TR(UPDATE_INSTALLED), text);
            } else {
                snprintf(text, sizeof text, RS_TR(INSTALL_FAILED), (unsigned long)rc);
                ui_message(RS_TR(UPDATE), text);
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
