/*
 * updater.h - updates of the homebrew through the server's relay, and the
 * compatibility check with the server (docs/SPEC.md, "Mises à jour").
 */
#ifndef RS_APP_UPDATER_H
#define RS_APP_UPDATER_H

#include <stdbool.h>

#include "app.h"

/* Version of this build (make VERSION=0.5.0), "dev" otherwise. */
#ifndef RS_VERSION
#define RS_VERSION "dev"
#endif

/* Tells the user, once per start, when the server is too old for this app
 * or the app too old for the server. */
void app_check_compatibility(app *a);

/* Looks for a newer version; with the user's agreement downloads the .cia,
 * verifies its signature and hash, and installs it with the AM service.
 * manual: started from the settings (reports "up to date" too). Returns
 * true when a new version was installed: the app must exit. */
bool app_check_update(app *a, bool manual);

#endif
