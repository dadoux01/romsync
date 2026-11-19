/*
 * msg.h - texts of the core and choice of the language.
 *
 * Texts of the core, in French and English (docs/SPEC.md, "Langues"). Each
 * message is a macro holding both languages; RS_TR(ID) picks the language
 * set by rs_set_language(). Both strings are literals, so GCC checks the
 * printf arguments against the French and the English text alike.
 *
 * Texts must only use characters of the console's code page (CP437, see
 * cp437.h): tests/test_msg.c checks every message of both languages.
 */
#ifndef RS_MSG_H
#define RS_MSG_H

typedef enum { RS_LANG_FR, RS_LANG_EN } rs_lang;

/* Language of the texts; English until set. */
void rs_set_language(rs_lang lang);
rs_lang rs_language(void);
/* "fr" gives French, anything else English. */
rs_lang rs_lang_from_code(const char *code);

#define RS_FR(fr, en) fr
#define RS_EN(fr, en) en
#define RS_TR(id) (rs_language() == RS_LANG_EN ? RS_MSG_##id(RS_EN) : RS_MSG_##id(RS_FR))

#define RS_MSG_NOMEM(L) L("Mémoire insuffisante", \
    "Out of memory")
#define RS_MSG_NOMEM_READING(L) L("Mémoire insuffisante pour lire %s", \
    "Out of memory to read %s")
#define RS_MSG_SERVER_BAD_REPLY(L) L("Réponse illisible du serveur", \
    "Unreadable answer from the server")
#define RS_MSG_TOKEN_MISSING(L) L("Jeton absent de la réponse", \
    "Token missing from the answer")
#define RS_MSG_DOWNLOAD_CORRUPT(L) L("Save téléchargée corrompue (hash différent)", \
    "Downloaded save corrupted (different hash)")
#define RS_MSG_UNEXPECTED_FILE_URL(L) L("Adresse de fichier inattendue", \
    "Unexpected file address")
#define RS_MSG_NETWORK_INIT(L) L("Initialisation réseau impossible", \
    "Cannot start the network")
#define RS_MSG_SERVER_UNREACHABLE_DETAIL(L) L("Serveur injoignable (%s)", \
    "Server unreachable (%s)")
#define RS_MSG_STATE_FILE_SET_ASIDE(L) L("Fichier illisible mis de côté : %s", \
    "Unreadable file set aside: %s")
#define RS_MSG_FOLDER_UNREADABLE(L) L("Dossier illisible : %s", \
    "Unreadable folder: %s")
#define RS_MSG_TWILIGHT_PROFILE_MISSING(L) L("Profil de conversion « twilight » introuvable.", \
    "Conversion profile \"twilight\" not found.")
#define RS_MSG_READ_FAILED(L) L("Lecture impossible : %s", \
    "Cannot read %s")
#define RS_MSG_ROM_HEADER_SHORT(L) L("%s : en-tête de ROM trop court", \
    "%s: ROM header too short")
#define RS_MSG_PROFILE_FIELD_NO_NAME(L) L("profil %s : champ sans nom", \
    "profile %s: field without a name")
#define RS_MSG_PROFILE_FIELD_TYPE(L) L("profil %s : type de champ non géré", \
    "profile %s: unsupported field type")
#define RS_MSG_PROFILE_COMPUTED(L) L("profil %s : valeur calculée inconnue", \
    "profile %s: unknown computed value")
#define RS_MSG_PROFILE_JSON(L) L("profil : JSON invalide", \
    "profile: invalid JSON")
#define RS_MSG_PROFILE_REQUIRED(L) L("profil : champ obligatoire manquant", \
    "profile: required field missing")
#define RS_MSG_PROFILE_HEADERS(L) L("profil %s : les en-têtes ne sont pas encore gérés", \
    "profile %s: headers are not supported yet")
#define RS_MSG_PROFILE_FOOTER_LENGTH(L) L("profil %s : longueur du pied manquante", \
    "profile %s: footer length missing")
#define RS_MSG_PROFILE_TOO_MANY_FIELDS(L) L("profil %s : trop de champs", \
    "profile %s: too many fields")
#define RS_MSG_PROFILE_FOOTER_SIZE(L) L("profil %s : pied de %zu octets, %zu déclarés", \
    "profile %s: %zu-byte footer, %zu declared")
#define RS_MSG_FILE_TOO_SHORT(L) L("%s : fichier trop court pour son pied de %zu octets", \
    "%s: file too short for its %zu-byte footer")
#define RS_MSG_FOOTER_NOT_FOUND(L) L("%s : pied de fichier introuvable", \
    "%s: footer not found")
#define RS_MSG_FOOTER_UNEXPECTED(L) L("%s : %s inattendu (%u)", \
    "%s: unexpected %s (%u)")
#define RS_MSG_FOOTER_SIZE_MISMATCH(L) L("%s : le pied annonce %u octets, le fichier en a %zu", \
    "%s: the footer announces %u bytes, the file holds %zu")
#define RS_MSG_PROFILES_DIR_NOT_FOUND(L) L("Dossier de profils introuvable : %s", \
    "Profile folder not found: %s")
#define RS_MSG_TOO_MANY_PROFILES(L) L("Trop de profils dans %s", \
    "Too many profiles in %s")
#define RS_MSG_CREATE_FAILED(L) L("Impossible de créer %s", \
    "Cannot create %s")
#define RS_MSG_PATH_NOT_FOUND(L) L("%s introuvable", \
    "%s not found")
#define RS_MSG_WRITE_FAILED(L) L("Écriture impossible : %s", \
    "Cannot write %s")
#define RS_MSG_MOVE_FAILED(L) L("Impossible de déplacer %s", \
    "Cannot move %s")
#define RS_MSG_TREE_INVALID_PATH(L) L("Chemin invalide dans la save : %s", \
    "Invalid path in the save: %s")
#define RS_MSG_TREE_CHANGING(L) L("Le dossier %s change pendant la lecture", \
    "The folder %s keeps changing while being read")
#define RS_MSG_TREE_BAD_ARCHIVE(L) L("Archive de save illisible", \
    "Unreadable save archive")
#define RS_MSG_SYNC_NEEDS_CHOICE(L) L("Deux appareils ont joué sans se synchroniser : choix à faire", \
    "Two devices played without syncing: choice needed")
#define RS_MSG_SYNC_IDENTICAL(L) L("Save identique à la version active", \
    "Save identical to the active version")
#define RS_MSG_SYNC_ARCHIVED(L) L("Save locale archivée sur le serveur", \
    "Local save archived on the server")
#define RS_MSG_SYNC_UPLOADED(L) L("Save envoyée", \
    "Save uploaded")
#define RS_MSG_SYNC_UPLOADED_DIVERGENT(L) L("Save envoyée (divergence)", \
    "Save uploaded (divergence)")
#define RS_MSG_SYNC_UPLOADED_NOT_ACTIVE(L) L("Save envoyée, mais une version plus récente reste active", \
    "Save uploaded, but a more recent version stays active")
#define RS_MSG_SYNC_OFFLINE(L) L("Serveur injoignable : %d envoi(s) en attente", \
    "Server unreachable: %d upload(s) waiting")
#define RS_MSG_SYNC_UNAUTHORIZED(L) L("Appareil non autorisé : appaire-le à nouveau.", \
    "Device not authorized: pair it again.")
#define RS_MSG_SYNC_REFUSED(L) L("Envoi refusé (%s) : %s. Copie conservée : %s", \
    "Upload refused (%s): %s. Copy kept: %s")
#define RS_MSG_SYNC_QUEUED(L) L("Save mise en file d'attente", \
    "Save queued")
#define RS_MSG_SYNC_OFFLINE_LAUNCH(L) L("Serveur injoignable : les envois partiront dès que le serveur répondra.", \
    "Server unreachable: uploads will leave as soon as the server answers.")
#define RS_MSG_SYNC_DOWNLOADED(L) L("Save du serveur téléchargée", \
    "Server save downloaded")
#define RS_MSG_SYNC_SHARED_ID(L) L("Plusieurs ROMs partagent l'identifiant %s : choisis d'abord de partager ou séparer leur save.", \
    "Several ROMs share the identifier %s: first choose to share or separate their save.")
#define RS_MSG_SERVER_OLDER(L) L("antérieur à 0.5.0", \
    "older than 0.5.0")
#define RS_MSG_SYNC_SERVER_TOO_OLD(L) L("Le serveur RomSync (%s) est trop ancien pour appliquer ce choix : rien n'a été envoyé ni écrasé. Mets d'abord à jour le serveur, puis recommence.", \
    "The RomSync server (%s) is too old to apply this choice: nothing was sent nor overwritten. Update the server first, then try again.")
#define RS_MSG_SYNC_SERVER_TOO_OLD_CONSOLE(L) L("Le serveur RomSync (%s) ne connaît pas encore cette console : mets d'abord à jour le serveur.", \
    "The RomSync server (%s) does not know this console yet: update the server first.")
#define RS_MSG_SYNC_UP_TO_DATE(L) L("Save à jour", \
    "Save up to date")
#define RS_MSG_SYNC_CHOICE_REQUIRED(L) L("Choix requis avant la synchronisation.", \
    "Choice required before syncing.")
#define RS_MSG_STATUS_UP_TO_DATE(L) L("à jour", \
    "up to date")
#define RS_MSG_STATUS_TO_UPLOAD(L) L("à envoyer", \
    "to upload")
#define RS_MSG_STATUS_TO_DOWNLOAD(L) L("à télécharger", \
    "to download")
#define RS_MSG_STATUS_OFFLINE(L) L("hors ligne", \
    "offline")
#define RS_MSG_STATUS_NEEDS_CHOICE(L) L("choix requis", \
    "choice required")
#define RS_MSG_STATUS_UNAVAILABLE(L) L("indisponible", \
    "unavailable")
#define RS_MSG_STATUS_NO_SAVE(L) L("pas de save", \
    "no save")
#define RS_MSG_STATUS_DIVERGED(L) L("choix à faire", \
    "choice needed")
#define RS_MSG_TWL_NEXT_TO_ROM(L) L("à côté de la ROM", \
    "next to the ROM")
#define RS_MSG_TWL_TWLM_FOLDER(L) L("dossier de TWiLight Menu++", \
    "TWiLight Menu++ folder")
#define RS_MSG_TWL_SAVES_FOLDER(L) L("dossier saves", \
    "saves folder")
#define RS_MSG_TWL_LOCATION_MISMATCH(L) L("TWiLight Menu++ range les saves dans : %s ; le forwarder dans : %s. Mets le même emplacement : SAVE_LOCATION=%d dans la section [NTR-FORWARDER] de sd:/_nds/ntr_forwarder.ini.", \
    "TWiLight Menu++ keeps the saves in: %s; the forwarder in: %s. Set the same location: SAVE_LOCATION=%d in the [NTR-FORWARDER] section of sd:/_nds/ntr_forwarder.ini.")
#define RS_MSG_TWL_SLOT_MISMATCH(L) L("Emplacement de save différent pour ce jeu : %d dans TWiLight Menu++, %d dans le forwarder. Choisis le même numéro de save dans les réglages du jeu des deux côtés (forwarder : maintenir Y au lancement).", \
    "Different save slot for this game: %d in TWiLight Menu++, %d in the forwarder. Choose the same save number in the game settings on both sides (forwarder: hold Y at launch).")
#define RS_MSG_UPDATE_SIGNATURE_UNREADABLE(L) L("Signature illisible : mise à jour refusée.", \
    "Unreadable signature: update refused.")
#define RS_MSG_UPDATE_SIGNATURE_INVALID(L) L("Signature invalide : cette mise à jour ne vient pas de RomSync, elle est refusée.", \
    "Invalid signature: this update does not come from RomSync, it is refused.")
#define RS_MSG_UPDATE_NOT_LISTED(L) L("%s ne figure pas dans SHA256SUMS : mise à jour refusée.", \
    "%s is not listed in SHA256SUMS: update refused.")
#define RS_MSG_UPDATE_HASH_MISMATCH(L) L("Le fichier téléchargé est altéré (hash différent) : mise à jour refusée.", \
    "The downloaded file is altered (different hash): update refused.")

/* Every message above, for the tests (test_msg.c). */
#define RS_CORE_MESSAGES(X) \
    X(NOMEM) \
    X(NOMEM_READING) \
    X(SERVER_BAD_REPLY) \
    X(TOKEN_MISSING) \
    X(DOWNLOAD_CORRUPT) \
    X(UNEXPECTED_FILE_URL) \
    X(NETWORK_INIT) \
    X(SERVER_UNREACHABLE_DETAIL) \
    X(STATE_FILE_SET_ASIDE) \
    X(FOLDER_UNREADABLE) \
    X(TWILIGHT_PROFILE_MISSING) \
    X(READ_FAILED) \
    X(ROM_HEADER_SHORT) \
    X(PROFILE_FIELD_NO_NAME) \
    X(PROFILE_FIELD_TYPE) \
    X(PROFILE_COMPUTED) \
    X(PROFILE_JSON) \
    X(PROFILE_REQUIRED) \
    X(PROFILE_HEADERS) \
    X(PROFILE_FOOTER_LENGTH) \
    X(PROFILE_TOO_MANY_FIELDS) \
    X(PROFILE_FOOTER_SIZE) \
    X(FILE_TOO_SHORT) \
    X(FOOTER_NOT_FOUND) \
    X(FOOTER_UNEXPECTED) \
    X(FOOTER_SIZE_MISMATCH) \
    X(PROFILES_DIR_NOT_FOUND) \
    X(TOO_MANY_PROFILES) \
    X(CREATE_FAILED) \
    X(PATH_NOT_FOUND) \
    X(WRITE_FAILED) \
    X(MOVE_FAILED) \
    X(TREE_INVALID_PATH) \
    X(TREE_CHANGING) \
    X(TREE_BAD_ARCHIVE) \
    X(SYNC_NEEDS_CHOICE) \
    X(SYNC_IDENTICAL) \
    X(SYNC_ARCHIVED) \
    X(SYNC_UPLOADED) \
    X(SYNC_UPLOADED_DIVERGENT) \
    X(SYNC_UPLOADED_NOT_ACTIVE) \
    X(SYNC_OFFLINE) \
    X(SYNC_UNAUTHORIZED) \
    X(SYNC_REFUSED) \
    X(SYNC_QUEUED) \
    X(SYNC_OFFLINE_LAUNCH) \
    X(SYNC_DOWNLOADED) \
    X(SYNC_SHARED_ID) \
    X(SERVER_OLDER) \
    X(SYNC_SERVER_TOO_OLD) \
    X(SYNC_SERVER_TOO_OLD_CONSOLE) \
    X(SYNC_UP_TO_DATE) \
    X(SYNC_CHOICE_REQUIRED) \
    X(STATUS_UP_TO_DATE) \
    X(STATUS_TO_UPLOAD) \
    X(STATUS_TO_DOWNLOAD) \
    X(STATUS_OFFLINE) \
    X(STATUS_NEEDS_CHOICE) \
    X(STATUS_UNAVAILABLE) \
    X(STATUS_NO_SAVE) \
    X(STATUS_DIVERGED) \
    X(TWL_NEXT_TO_ROM) \
    X(TWL_TWLM_FOLDER) \
    X(TWL_SAVES_FOLDER) \
    X(TWL_LOCATION_MISMATCH) \
    X(TWL_SLOT_MISMATCH) \
    X(UPDATE_SIGNATURE_UNREADABLE) \
    X(UPDATE_SIGNATURE_INVALID) \
    X(UPDATE_NOT_LISTED) \
    X(UPDATE_HASH_MISMATCH)

#endif
