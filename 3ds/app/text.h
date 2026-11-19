/*
 * text.h - texts of the 3DS screens.
 *
 * Texts of the 3DS screens, in French and English, used as RS_TR(ID) like
 * those of the core (see core/msg.h).
 */
#ifndef RS_TEXT_H
#define RS_TEXT_H

#include "../core/msg.h"

#define RS_MSG_ERROR(L) L("Erreur", \
    "Error")
#define RS_MSG_WARNING(L) L("Attention", \
    "Warning")
#define RS_MSG_SD_PROFILES_IGNORED(L) L("Profils de la carte SD ignorés", \
    "SD card profiles ignored")
#define RS_MSG_PAIRING(L) L("Appairage", \
    "Pairing")
#define RS_MSG_PAIRING_HELP(L) L("Sur le site de RomSync, clique « Ajouter un appareil » pour obtenir un code, puis saisis l'adresse du serveur (ex. http://192.168.1.10:8085), le code et le nom de cette console.\n\nTailscale n'existe pas sur 3DS : le serveur doit être joignable sur le réseau local.", \
    "On the RomSync website, click \"Add a device\" to get a code, then enter the server address (e.g. http://192.168.1.10:8085), the code and the name of this console.\n\nTailscale does not exist on 3DS: the server must be reachable on the local network.")
#define RS_MSG_SERVER_ADDRESS(L) L("Adresse du serveur", \
    "Server address")
#define RS_MSG_PAIRING_CODE(L) L("Code d'appairage (ex. K7QM-4XPA)", \
    "Pairing code (e.g. K7QM-4XPA)")
#define RS_MSG_DEVICE_NAME(L) L("Nom de cet appareil", \
    "Name of this device")
#define RS_MSG_PAIRING_CANCELLED(L) L("Appairage annulé.", \
    "Pairing cancelled.")
#define RS_MSG_RETRY(L) L("Recommencer", \
    "Try again")
#define RS_MSG_QUIT(L) L("Quitter", \
    "Quit")
#define RS_MSG_INVALID_ADDRESS(L) L("Adresse invalide", \
    "Invalid address")
#define RS_MSG_ADDRESS_EXAMPLE(L) L("Exemple d'adresse valide : http://192.168.1.10:8085", \
    "Example of a valid address: http://192.168.1.10:8085")
#define RS_MSG_CONNECTING(L) L("Connexion au serveur...", \
    "Connecting to the server...")
#define RS_MSG_CODE_EXPIRED(L) L("Code expiré ou déjà utilisé : génère un nouveau code sur le site.", \
    "Code expired or already used: generate a new code on the website.")
#define RS_MSG_TOO_MANY_TRIES(L) L("Trop d'essais : attends une minute.", \
    "Too many tries: wait a minute.")
#define RS_MSG_PAIRING_FAILED(L) L("Appairage impossible", \
    "Cannot pair")
#define RS_MSG_PAIRING_DONE(L) L("Appairage réussi", \
    "Paired")
#define RS_MSG_PAIRING_DONE_TEXT(L) L("Cette console est maintenant reliée à ton compte RomSync.", \
    "This console is now linked to your RomSync account.")
#define RS_MSG_SUBFOLDERS(L) L("Sous-dossiers", \
    "Sub-folders")
#define RS_MSG_SUBFOLDERS_OF_THIS(L) L("Chercher aussi les ROMs dans les sous-dossiers de ce dossier ?", \
    "Also look for ROMs in the sub-folders of this folder?")
#define RS_MSG_YES(L) L("Oui", \
    "Yes")
#define RS_MSG_NO(L) L("Non", \
    "No")
#define RS_MSG_ROM_FOLDERS(L) L("Dossiers de ROMs", \
    "ROM folders")
#define RS_MSG_EIGHT_FOLDERS_MAX(L) L("Huit dossiers au plus.", \
    "Eight folders at most.")
#define RS_MSG_USE_ROMS_NDS(L) L("Le dossier sdmc:/roms/nds/ existe. L'utiliser comme dossier de ROMs ?", \
    "The sdmc:/roms/nds/ folder exists. Use it as the ROM folder?")
#define RS_MSG_CHOOSE_ANOTHER(L) L("Choisir un autre", \
    "Choose another")
#define RS_MSG_SUBFOLDERS_OF_IT(L) L("Chercher aussi les ROMs dans ses sous-dossiers ?", \
    "Also look for ROMs in its sub-folders?")
#define RS_MSG_CHOOSE_ROM_FOLDER(L) L("Choisis le dossier où sont tes ROMs DS.", \
    "Choose the folder holding your DS ROMs.")
#define RS_MSG_ADD_ANOTHER_FOLDER(L) L("Ajouter un autre dossier de ROMs ?", \
    "Add another ROM folder?")
#define RS_MSG_SCANNING(L) L("Recherche des ROMs", \
    "Looking for ROMs")
#define RS_MSG_READING_FOLDERS(L) L("Lecture des dossiers de ROMs...", \
    "Reading the ROM folders...")
#define RS_MSG_NO_ROM_IN(L) L("Aucune ROM DS (.nds) trouvée dans %s.\n", \
    "No DS ROM (.nds) found in %s.\n")
#define RS_MSG_NO_ROM_IN_TREE(L) L("Aucune ROM DS (.nds) trouvée dans %s ni ses sous-dossiers.\n", \
    "No DS ROM (.nds) found in %s or its sub-folders.\n")
#define RS_MSG_SLOT_CHANGED_TEXT(L) L("%s utilise maintenant l'emplacement de save %d (%s). Ce fichier existe mais n'a jamais été synchronisé pour ce jeu : c'est sans doute une ancienne save.\n\nA : la mettre de côté dans .backup (la save du serveur sera téléchargée)\nB : l'envoyer quand même : elle deviendra la save active (l'autre reste dans l'historique)", \
    "%s now uses save slot %d (%s). This file exists but was never synced for this game: it is probably an old save.\n\nA: set it aside in .backup (the server save will be downloaded)\nB: send it anyway: it becomes the active save (the other one stays in the history)")
#define RS_MSG_SLOT_CHANGED(L) L("Emplacement de save changé", \
    "Save slot changed")
#define RS_MSG_SET_ASIDE(L) L("Mettre de côté", \
    "Set aside")
#define RS_MSG_SEND(L) L("Envoyer", \
    "Send")
#define RS_MSG_DIVERGENCE_TEXT(L) L("%s\n\nDeux appareils ont joué sans se synchroniser.\n- Serveur : save du %.10s à %.5s (%s).\n- Console : save modifiée depuis la dernière synchro, qui ne part pas de celle du serveur.\n\nEnvoyer la tienne : elle devient la save active.\nPrendre celle du serveur : la tienne reste dans l'historique du site et dans .backup.\nPlus tard : rien n'est envoyé ni écrasé.", \
    "%s\n\nTwo devices played without syncing.\n- Server: save of %.10s at %.5s (%s).\n- Console: save changed since the last sync, which does not start from the server one.\n\nSend yours: it becomes the active save.\nTake the server one: yours stays in the website history and in .backup.\nLater: nothing is sent nor overwritten.")
#define RS_MSG_WEBSITE(L) L("site web", \
    "website")
#define RS_MSG_CHOICE_NEEDED(L) L("Choix à faire", \
    "Choice needed")
#define RS_MSG_SEND_MY_SAVE(L) L("envoyer ma save locale", \
    "send my local save")
#define RS_MSG_TAKE_SERVER(L) L("prendre celle du serveur", \
    "take the server one")
#define RS_MSG_LATER(L) L("plus tard", \
    "later")
#define RS_MSG_TAKING_SERVER_SAVE(L) L("Envoi de ta save comme ancienne version (inactive), puis téléchargement de celle du serveur...", \
    "Sending your save as an old (inactive) version, then downloading the server one...")
#define RS_MSG_SENDING_LOCAL_SAVE(L) L("Envoi de ta save : elle devient la save active...", \
    "Sending your save: it becomes the active one...")
#define RS_MSG_SERVER_SAVE_TAKEN(L) L("Save du serveur récupérée. Ta save de la console reste dans l'historique du site (version inactive, restaurable ou supprimable) et dans le dossier .backup.", \
    "Server save retrieved. Your console save stays in the website history (inactive version, which you can restore or delete) and in the .backup folder.")
#define RS_MSG_LOCAL_SAVE_SENT(L) L("Ta save de la console est envoyée : c'est la save active. Celle d'avant reste dans l'historique du site.", \
    "Your console save is sent: it is the active one. The previous one stays in the website history.")
#define RS_MSG_CHOICE_POSTPONED(L) L("Choix reporté : rien n'a été envoyé ni écrasé.", \
    "Choice postponed: nothing was sent nor overwritten.")
#define RS_MSG_ANOTHER_SAVE_ARRIVED(L) L("Une autre save vient d'arriver : relance la synchronisation.", \
    "Another save just arrived: sync again.")
#define RS_MSG_DOWNLOADED(L) L("Save du serveur téléchargée.", \
    "Server save downloaded.")
#define RS_MSG_UPLOADED(L) L("Save envoyée.", \
    "Save uploaded.")
#define RS_MSG_OFFLINE_QUEUED(L) L("Hors ligne : %d envoi(s) en attente", \
    "Offline: %d upload(s) waiting")
#define RS_MSG_SYNCED(L) L("Synchronisé", \
    "Synced")
#define RS_MSG_SYNC(L) L("Synchronisation", \
    "Sync")
#define RS_MSG_SENDING_QUEUE(L) L("Envoi des saves en attente...", \
    "Sending the waiting saves...")
#define RS_MSG_UNAUTHORIZED(L) L("Appareil non autorisé", \
    "Device not authorized")
#define RS_MSG_UNAUTHORIZED_TEXT(L) L("Le serveur refuse cette console (appareil révoqué ?). Appaire-la de nouveau depuis les réglages (SELECT).", \
    "The server refuses this console (device revoked?). Pair it again from the settings (SELECT).")
#define RS_MSG_OFFLINE_QUEUING(L) L("Hors ligne : mise en file", \
    "Offline: queuing")
#define RS_MSG_LAUNCH(L) L("Lancer", \
    "Launch")
#define RS_MSG_LAUNCH_SHARED_ID(L) L("Plusieurs ROMs partagent l'identifiant de ce jeu : choisis d'abord de partager ou séparer leur save (Y).", \
    "Several ROMs share the identifier of this game: first choose to share or separate their save (Y).")
#define RS_MSG_LAUNCH_FAILED(L) L("Lancement impossible", \
    "Cannot launch")
#define RS_MSG_BEFORE_LAUNCH(L) L("Avant le lancement", \
    "Before the launch")
#define RS_MSG_LAUNCH_ANYWAY(L) L("Lancer quand même", \
    "Launch anyway")
#define RS_MSG_CANCEL(L) L("Annuler", \
    "Cancel")
#define RS_MSG_OFFLINE(L) L("Hors ligne", \
    "Offline")
#define RS_MSG_OFFLINE_LAUNCH(L) L("Serveur injoignable : la partie se lance avec la save locale. Rouvre RomSync après avoir joué : ta save partira dès que le serveur répondra.", \
    "Server unreachable: the game starts with the local save. Open RomSync again after playing: your save will leave as soon as the server answers.")
#define RS_MSG_LAUNCHING(L) L("Lancement", \
    "Launching")
#define RS_MSG_STARTING_GAME(L) L("Démarrage du jeu...\n\nAprès la partie, rouvre RomSync pour envoyer ta save.", \
    "Starting the game...\n\nAfter playing, open RomSync again to send your save.")
#define RS_MSG_SHARING_TEXT(L) L("%s partage l'identifiant %s avec %d autre(s) ROM(s) (variante, traduction, hack).\n\nA : partager la même save\nB : séparer (nouvel identifiant à nommer)", \
    "%s shares the identifier %s with %d other ROM(s) (variant, translation, hack).\n\nA: share the same save\nB: separate (new identifier to name)")
#define RS_MSG_SHARED_SAVE(L) L("Save partagée ?", \
    "Shared save?")
#define RS_MSG_SHARE(L) L("Partager", \
    "Share")
#define RS_MSG_SEPARATE(L) L("Séparer", \
    "Separate")
#define RS_MSG_SEPARATE_NAME(L) L("Nom de la save séparée (a-z, 0-9, -)", \
    "Name of the separate save (a-z, 0-9, -)")
#define RS_MSG_INVALID_NAME(L) L("Nom invalide", \
    "Invalid name")
#define RS_MSG_INVALID_NAME_TEXT(L) L("Lettres sans accents, chiffres, espaces ou tirets, 32 au plus.", \
    "Letters without accents, digits, spaces or dashes, 32 at most.")
#define RS_MSG_WITH_SUBFOLDERS(L) L(" (+ sous-dossiers)", \
    " (+ sub-folders)")
#define RS_MSG_FOLDERS_KEYS(L) L("A : sous-dossiers oui/non\nX : ajouter un dossier\nY : retirer ce dossier\nB : retour\n", \
    "A: sub-folders yes/no\nX: add a folder\nY: remove this folder\nB: back\n")
#define RS_MSG_SETTINGS(L) L("Réglages", \
    "Settings")
#define RS_MSG_SETTING_BACKUPS(L) L("Copies .backup gardées par save", \
    ".backup copies kept per save")
#define RS_MSG_SETTING_AUTO_UPDATE(L) L("Rechercher les mises à jour au démarrage", \
    "Check for updates at start")
#define RS_MSG_SETTING_CHECK_NOW(L) L("Rechercher une mise à jour maintenant", \
    "Check for an update now")
#define RS_MSG_SETTING_PAIR_AGAIN(L) L("Appairer de nouveau", \
    "Pair again")
#define RS_MSG_SETTING_LANGUAGE(L) L("Langue", \
    "Language")
#define RS_MSG_LANGUAGE_SYSTEM(L) L("console", \
    "console")
#define RS_MSG_BACK(L) L("Retour", \
    "Back")
#define RS_MSG_YES_LOWER(L) L("oui", \
    "yes")
#define RS_MSG_NO_LOWER(L) L("non", \
    "no")
#define RS_MSG_SETTINGS_INFO(L) L("\nServeur : %s\nAppareil : %s\nRomSync %s\n", \
    "\nServer: %s\nDevice: %s\nRomSync %s\n")
#define RS_MSG_SETTINGS_KEYS(L) L("\n\nA : choisir\nGauche/Droite : changer la valeur\nB : retour\n", \
    "\n\nA: choose\nLeft/Right: change the value\nB: back\n")
#define RS_MSG_NETWORK(L) L("Réseau", \
    "Network")
#define RS_MSG_NETWORK_DOWN(L) L("Le service réseau n'a pas démarré : RomSync fonctionnera hors ligne.", \
    "The network service did not start: RomSync will work offline.")
#define RS_MSG_PROFILE_MISSING(L) L("Profil manquant", \
    "Missing profile")
#define RS_MSG_PROFILE_MISSING_TEXT(L) L("Le profil de conversion « twilight » est introuvable : réinstalle RomSync.", \
    "The \"twilight\" conversion profile was not found: reinstall RomSync.")
#define RS_MSG_TWLM_MISSING(L) L("sd:/_nds/TWiLightMenu/ est introuvable : RomSync suppose les réglages par défaut (saves dans le dossier saves/ de chaque dossier de ROMs).", \
    "sd:/_nds/TWiLightMenu/ was not found: RomSync assumes the default settings (saves in the saves/ folder of each ROM folder).")
#define RS_MSG_NO_ROMS(L) L("\nAucune ROM DS trouvée.\nSELECT : réglages, pour choisir les dossiers.\n", \
    "\nNo DS ROM found.\nSELECT: settings, to choose the folders.\n")
#define RS_MSG_ERROR_LOWER(L) L("erreur", \
    "error")
#define RS_MSG_CONFLICT_FOOTNOTE(L) L("* conflit résolu automatiquement", \
    "* conflict resolved automatically")
#define RS_MSG_DETAIL_ID(L) L("Identifiant : %s\n", \
    "Identifier: %s\n")
#define RS_MSG_DETAIL_ROM(L) L("ROM : ", \
    "ROM: ")
#define RS_MSG_DETAIL_SAVE(L) L("\nSave : ", \
    "\nSave: ")
#define RS_MSG_DETAIL_SLOT(L) L("\nEmplacement de save : %d%s\n", \
    "\nSave slot: %d%s\n")
#define RS_MSG_DETAIL_STATE(L) L("État : %s%s", \
    "State: %s%s")
#define RS_MSG_DETAIL_LAST_SYNC(L) L("Dernière synchro : %.10s %.5s\n", \
    "Last sync: %.10s %.5s\n")
#define RS_MSG_DETAIL_PENDING(L) L("%d envoi(s) en attente", \
    "%d upload(s) waiting")
#define RS_MSG_DETAIL_CHOICE(L) L("Choix à faire : deux appareils ont\njoué sans se synchroniser (A).", \
    "Choice needed: two devices played\nwithout syncing (A).")
#define RS_MSG_DETAIL_CONFLICT(L) L("Divergence : voir l'historique\nsur le site.", \
    "Divergence: see the history\non the website.")
#define RS_MSG_DETAIL_SHARED(L) L("Partage l'identifiant %s\navec %d autre(s) ROM(s).\n", \
    "Shares the identifier %s\nwith %d other ROM(s).\n")
#define RS_MSG_KEYS_SYNC(L) L("A : synchroniser ce jeu   R : tout\n", \
    "A: sync this game   R: all\n")
#define RS_MSG_KEYS_LAUNCH(L) L("X : lancer", \
    "X: launch")
#define RS_MSG_KEYS_SHARE(L) L("   Y : partager/séparer", \
    "   Y: share/separate")
#define RS_MSG_KEYS_MENU(L) L("\nSELECT : réglages   START : quitter\n", \
    "\nSELECT: settings   START: quit\n")
#define RS_MSG_BROWSER_ROMS(L) L("%d ROM(s) DS dans ce dossier\n\n", \
    "%d DS ROM(s) in this folder\n\n")
#define RS_MSG_BROWSER_NO_SUBFOLDER(L) L("(aucun sous-dossier)\n", \
    "(no sub-folder)\n")
#define RS_MSG_BROWSER_TITLE(L) L("Choisir un dossier de ROMs", \
    "Choose a ROM folder")
#define RS_MSG_BROWSER_KEYS(L) L("Haut/Bas : se déplacer\nA        : ouvrir le dossier\nB        : dossier parent\nX        : choisir ce dossier\nSTART    : annuler\n", \
    "Up/Down: move\nA      : open the folder\nB      : parent folder\nX      : choose this folder\nSTART  : cancel\n")
#define RS_MSG_FORWARDER_MISSING(L) L("sd:/_nds/ntr-forwarder/sdcard.nds est introuvable%s.\n\nDans le « DS Game Forwarder Pack » (github.com/RocketRobz/NTR_Forwarder, page Releases), copie le contenu du dossier « for SD Card root » (le dossier _nds) à la racine de la carte SD, pas le dossier lui-même.", \
    "sd:/_nds/ntr-forwarder/sdcard.nds was not found%s.\n\nIn the \"DS Game Forwarder Pack\" (github.com/RocketRobz/NTR_Forwarder, Releases page), copy the content of the \"for SD Card root\" folder (the _nds folder) to the root of the SD card, not the folder itself.")
#define RS_MSG_FORWARDER_COPIED_AS_IS(L) L(" (le dossier « for SD Card root » a été copié tel quel)", \
    " (the \"for SD Card root\" folder was copied as it is)")
#define RS_MSG_BOOTSTRAP_MISSING(L) L("bootstrap.cia de YANBF n'est pas installé.\n\nTélécharge bootstrap.cia (github.com/YANBForwarder/YANBF, page Releases) et installe-le avec FBI.", \
    "YANBF's bootstrap.cia is not installed.\n\nDownload bootstrap.cia (github.com/YANBForwarder/YANBF, Releases page) and install it with FBI.")
#define RS_MSG_BOOTSTRAP_REFUSED(L) L("Le système a refusé de lancer bootstrap.cia (erreur 0x%08lX). Vérifie qu'il est installé (avec FBI), et installe RomSync en .cia : le lancement peut ne pas fonctionner depuis le Homebrew Launcher.", \
    "The system refused to start bootstrap.cia (error 0x%08lX). Check that it is installed (with FBI), and install RomSync as a .cia: launching may not work from the Homebrew Launcher.")
#define RS_MSG_SERVER_TOO_OLD_TEXT(L) L("Le serveur RomSync (%s) est trop ancien pour cette version de RomSync (%s).\n\nMets d'abord à jour le serveur (nouvelle image Docker). En attendant, le choix en cas de divergence n'est pas disponible.", \
    "The RomSync server (%s) is too old for this version of RomSync (%s).\n\nUpdate the server first (new Docker image). Until then, the choice after a divergence is not available.")
#define RS_MSG_SERVER_TOO_OLD(L) L("Serveur trop ancien", \
    "Server too old")
#define RS_MSG_APP_TOO_OLD_TEXT(L) L("Cette version de RomSync (%s) est trop ancienne pour le serveur, qui demande au moins la %s : mets-la à jour (SELECT, puis « Rechercher une mise à jour »).", \
    "This version of RomSync (%s) is too old for the server, which requires at least %s: update it (SELECT, then \"Check for an update now\").")
#define RS_MSG_APP_TOO_OLD(L) L("RomSync trop ancien", \
    "RomSync too old")
#define RS_MSG_INSTALLING_PROGRESS(L) L("Installation...\n\n%u / %u Kio", \
    "Installing...\n\n%u / %u KiB")
#define RS_MSG_UPDATE(L) L("Mise à jour", \
    "Update")
#define RS_MSG_UPDATE_DEV(L) L("Version de développement : pas de mise à jour automatique.", \
    "Development version: no automatic update.")
#define RS_MSG_UPDATE_OFFLINE(L) L("Serveur injoignable : réessaie quand la console est connectée.", \
    "Server unreachable: try again when the console is connected.")
#define RS_MSG_UPDATE_LOOKING(L) L("Recherche d'une nouvelle version...", \
    "Looking for a new version...")
#define RS_MSG_UPDATE_UP_TO_DATE(L) L("RomSync est à jour.", \
    "RomSync is up to date.")
#define RS_MSG_UPDATE_NO_RELAY(L) L("Le serveur ne propose pas de mise à jour (relais désactivé, serveur trop ancien ou aucune version publiée).", \
    "The server offers no update (relay disabled, server too old or no release published).")
#define RS_MSG_UPDATE_NOTES(L) L("Version actuelle : %s\n\n%s", \
    "Current version: %s\n\n%s")
#define RS_MSG_UPDATE_AVAILABLE(L) L("RomSync %s est disponible", \
    "RomSync %s is available")
#define RS_MSG_DOWNLOAD_LOWER(L) L("télécharger", \
    "download")
#define RS_MSG_DOWNLOADING(L) L("Téléchargement...", \
    "Downloading...")
#define RS_MSG_VERIFYING(L) L("Vérification de la signature...", \
    "Verifying the signature...")
#define RS_MSG_UPDATE_REFUSED(L) L("Mise à jour refusée", \
    "Update refused")
#define RS_MSG_UPDATE_READY(L) L("RomSync %s est téléchargée et vérifiée.\n\nL'installer maintenant ? RomSync se fermera ensuite : relance-le depuis le menu HOME.", \
    "RomSync %s is downloaded and verified.\n\nInstall it now? RomSync will then close: start it again from the HOME menu.")
#define RS_MSG_INSTALL(L) L("Installer", \
    "Install")
#define RS_MSG_INSTALL_LOWER(L) L("installer", \
    "install")
#define RS_MSG_CANCEL_LOWER(L) L("annuler", \
    "cancel")
#define RS_MSG_UPDATE_INSTALLED_TEXT(L) L("RomSync %s est installée. RomSync va se fermer : relance-le depuis le menu HOME.", \
    "RomSync %s is installed. RomSync will close: start it again from the HOME menu.")
#define RS_MSG_UPDATE_INSTALLED(L) L("Mise à jour installée", \
    "Update installed")
#define RS_MSG_INSTALL_FAILED(L) L("L'installation a échoué (erreur 0x%08lX). La version actuelle reste en place.\n\nDepuis le Homebrew Launcher, installe plutôt RomSync en .cia avec FBI.", \
    "The installation failed (error 0x%08lX). The current version stays in place.\n\nFrom the Homebrew Launcher, install RomSync as a .cia with FBI instead.")
#define RS_MSG_OK_KEY(L) L("A : OK", \
    "A: OK")

/* Every message above, for the tests (test_msg.c). */
#define RS_APP_TEXTS(X) \
    X(ERROR) \
    X(WARNING) \
    X(SD_PROFILES_IGNORED) \
    X(PAIRING) \
    X(PAIRING_HELP) \
    X(SERVER_ADDRESS) \
    X(PAIRING_CODE) \
    X(DEVICE_NAME) \
    X(PAIRING_CANCELLED) \
    X(RETRY) \
    X(QUIT) \
    X(INVALID_ADDRESS) \
    X(ADDRESS_EXAMPLE) \
    X(CONNECTING) \
    X(CODE_EXPIRED) \
    X(TOO_MANY_TRIES) \
    X(PAIRING_FAILED) \
    X(PAIRING_DONE) \
    X(PAIRING_DONE_TEXT) \
    X(SUBFOLDERS) \
    X(SUBFOLDERS_OF_THIS) \
    X(YES) \
    X(NO) \
    X(ROM_FOLDERS) \
    X(EIGHT_FOLDERS_MAX) \
    X(USE_ROMS_NDS) \
    X(CHOOSE_ANOTHER) \
    X(SUBFOLDERS_OF_IT) \
    X(CHOOSE_ROM_FOLDER) \
    X(ADD_ANOTHER_FOLDER) \
    X(SCANNING) \
    X(READING_FOLDERS) \
    X(NO_ROM_IN) \
    X(NO_ROM_IN_TREE) \
    X(SLOT_CHANGED_TEXT) \
    X(SLOT_CHANGED) \
    X(SET_ASIDE) \
    X(SEND) \
    X(DIVERGENCE_TEXT) \
    X(WEBSITE) \
    X(CHOICE_NEEDED) \
    X(SEND_MY_SAVE) \
    X(TAKE_SERVER) \
    X(LATER) \
    X(TAKING_SERVER_SAVE) \
    X(SENDING_LOCAL_SAVE) \
    X(SERVER_SAVE_TAKEN) \
    X(LOCAL_SAVE_SENT) \
    X(CHOICE_POSTPONED) \
    X(ANOTHER_SAVE_ARRIVED) \
    X(DOWNLOADED) \
    X(UPLOADED) \
    X(OFFLINE_QUEUED) \
    X(SYNCED) \
    X(SYNC) \
    X(SENDING_QUEUE) \
    X(UNAUTHORIZED) \
    X(UNAUTHORIZED_TEXT) \
    X(OFFLINE_QUEUING) \
    X(LAUNCH) \
    X(LAUNCH_SHARED_ID) \
    X(LAUNCH_FAILED) \
    X(BEFORE_LAUNCH) \
    X(LAUNCH_ANYWAY) \
    X(CANCEL) \
    X(OFFLINE) \
    X(OFFLINE_LAUNCH) \
    X(LAUNCHING) \
    X(STARTING_GAME) \
    X(SHARING_TEXT) \
    X(SHARED_SAVE) \
    X(SHARE) \
    X(SEPARATE) \
    X(SEPARATE_NAME) \
    X(INVALID_NAME) \
    X(INVALID_NAME_TEXT) \
    X(WITH_SUBFOLDERS) \
    X(FOLDERS_KEYS) \
    X(SETTINGS) \
    X(SETTING_BACKUPS) \
    X(SETTING_AUTO_UPDATE) \
    X(SETTING_CHECK_NOW) \
    X(SETTING_PAIR_AGAIN) \
    X(SETTING_LANGUAGE) \
    X(LANGUAGE_SYSTEM) \
    X(BACK) \
    X(YES_LOWER) \
    X(NO_LOWER) \
    X(SETTINGS_INFO) \
    X(SETTINGS_KEYS) \
    X(NETWORK) \
    X(NETWORK_DOWN) \
    X(PROFILE_MISSING) \
    X(PROFILE_MISSING_TEXT) \
    X(TWLM_MISSING) \
    X(NO_ROMS) \
    X(ERROR_LOWER) \
    X(CONFLICT_FOOTNOTE) \
    X(DETAIL_ID) \
    X(DETAIL_ROM) \
    X(DETAIL_SAVE) \
    X(DETAIL_SLOT) \
    X(DETAIL_STATE) \
    X(DETAIL_LAST_SYNC) \
    X(DETAIL_PENDING) \
    X(DETAIL_CHOICE) \
    X(DETAIL_CONFLICT) \
    X(DETAIL_SHARED) \
    X(KEYS_SYNC) \
    X(KEYS_LAUNCH) \
    X(KEYS_SHARE) \
    X(KEYS_MENU) \
    X(BROWSER_ROMS) \
    X(BROWSER_NO_SUBFOLDER) \
    X(BROWSER_TITLE) \
    X(BROWSER_KEYS) \
    X(FORWARDER_MISSING) \
    X(FORWARDER_COPIED_AS_IS) \
    X(BOOTSTRAP_MISSING) \
    X(BOOTSTRAP_REFUSED) \
    X(SERVER_TOO_OLD_TEXT) \
    X(SERVER_TOO_OLD) \
    X(APP_TOO_OLD_TEXT) \
    X(APP_TOO_OLD) \
    X(INSTALLING_PROGRESS) \
    X(UPDATE) \
    X(UPDATE_DEV) \
    X(UPDATE_OFFLINE) \
    X(UPDATE_LOOKING) \
    X(UPDATE_UP_TO_DATE) \
    X(UPDATE_NO_RELAY) \
    X(UPDATE_NOTES) \
    X(UPDATE_AVAILABLE) \
    X(DOWNLOAD_LOWER) \
    X(DOWNLOADING) \
    X(VERIFYING) \
    X(UPDATE_REFUSED) \
    X(UPDATE_READY) \
    X(INSTALL) \
    X(INSTALL_LOWER) \
    X(CANCEL_LOWER) \
    X(UPDATE_INSTALLED_TEXT) \
    X(UPDATE_INSTALLED) \
    X(INSTALL_FAILED) \
    X(OK_KEY)

#endif
