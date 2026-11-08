# RomSync — spécification

Nov 7, 2026 · @Michael

## Vue d'ensemble

RomSync garde une seule save à jour par jeu et par compte, sur un serveur auto-hébergé, et chaque appareil la récupère avant de jouer puis la renvoie après. Toutes les anciennes versions restent consultables et restaurables, selon une règle de conservation réglable.

**Périmètre v1**

- Nintendo DS uniquement : saves en jeu (cartouche), pas de save states.
- Plusieurs utilisateurs : un admin, les autres comptes créés par invitation.
- Appareils : Linux, macOS, Windows, Android (appli Flutter), 3DS (homebrew), DS physique avec flashcard (import/export via l'interface web).
- Le client sert aussi de lanceur : il détecte les ROMs locales, lance l'émulateur choisi et synchronise autour de la partie.
- Accès hors du réseau local via Tailscale ; le service n'est pas pensé pour être exposé directement sur Internet.

**Hors périmètre v1**

- Hébergement ou distribution de ROMs : les ROMs restent sur chaque appareil.
- Save states, autres consoles (GBA, 3DS natif…), succès, partage de saves entre comptes.

**Limites connues**

- DS Lite + DSTT : aucune synchronisation automatique possible (Wi-Fi WEP uniquement, pas d'appli réseau sur flashcard). La save passe par la page d'import/export du site.
- 3DS : l'appli ne tourne pas pendant le jeu DS (lancé depuis TWiLight Menu++, ou depuis RomSync par un forwarder YANBF, qui quitte alors l'appli) ; l'envoi de la save se fait donc au prochain démarrage de l'appli, pas à la fin de la partie.

## Architecture

Un seul binaire Go sert l'API et l'interface web ; tous les clients parlent à la même API REST, et le serveur ne contacte jamais les appareils.

&#91;embedded content: architecture · 4 types d'appareils, 1 serveur\]

Les trois applis appellent l'API directement ; le navigateur passe par le site, qui utilise la même API. La 3DS ne peut pas utiliser Tailscale et doit donc être sur le réseau local.

| Composant | Techno | Rôle |
| --- | --- | --- |
| Serveur | Go, SQLite, stockage fichiers | API, comptes, appareils, versions de saves, rétention |
| Interface web | SPA compilée et embarquée dans le binaire Go | Comptes, invitations, appairage, historique, restauration, import/export manuel |
| Client | Flutter (Linux, macOS, Windows, Android) | Scan des ROMs, lanceur d'émulateurs, conversion et synchro des saves |
| Homebrew 3DS | C, devkitPro (libctru), libcurl | Scan de la SD, synchro des saves, lancement facultatif via YANBF et nds-bootstrap |

**Déploiement**

- Une image Docker, un volume `/data` qui contient la base SQLite et les fichiers de saves.
- Pas de base externe ni de cache : un `docker compose up` suffit sur le homelab.
- HTTPS : fourni par Tailscale (`tailscale serve` ou certificats MagicDNS) ; le serveur parle HTTP en interne.
- Sauvegarde du service : copier `/data` (avec un `VACUUM INTO` pour la base) suffit.

## Modèle de données

Sept tables SQLite suffisent ; le contenu des saves vit hors de la base, dans des fichiers nommés par leur hash. Le schéma évolue par migrations SQL versionnées dans le dépôt (`server/internal/db/migrations`).

| Table | Champs principaux | Notes |
| --- | --- | --- |
| `users` | id, username, password\_hash (Argon2id), role (`admin`/`user`), created\_at, disabled\_at, retention\_policy | Le premier compte créé devient admin ; `disabled_at` non nul bloque la connexion et les appareils du compte |
| `sessions` | token\_hash, user\_id, created\_at, expires\_at | Session web, 30 jours, prolongée à chaque utilisation |
| `invites` | id, token\_hash, created\_by, created\_at, expires\_at, used\_by, used\_at | Lien à usage unique, 7 jours par défaut |
| `devices` | id, user\_id, name, platform, token\_hash, created\_at, last\_seen\_at, revoked\_at, clock\_skew\_at | Un jeton par appareil, révocable ; `clock_skew_at` = dernier décalage d'horloge détecté |
| `games` | id, user\_id, game\_code, title, region, chip\_size, first\_seen\_at, retention\_policy | Unique sur (user\_id, game\_code) ; `chip_size` = taille de puce mémorisée ; `retention_policy` NULL = hérite du compte |
| `save_versions` | id, game\_id, blob\_hash, size, saved\_at, saved\_at\_reported, uploaded\_at, device\_id, emulator, base\_version\_id, upload\_id, is\_active, conflict, pinned, note, size\_event, size\_event\_from | Une seule version active par jeu ; `upload_id` unique par compte ; `conflict` = divergence détectée à l'envoi ; `size_event` = coupe ou changement de taille de puce (voir « Taille réelle ») |
| `pair_codes` | code\_hash, user\_id, expires\_at, used\_at | Code d'appairage, 10 minutes |

Les identifiants (`id`) sont des entiers ; les dates sont stockées et échangées en UTC, au format RFC 3339.

**Stockage des fichiers**

- Chemin : `/data/blobs/<2 premiers caractères du SHA-256>/<SHA-256>`.
- Une save identique envoyée deux fois n'est stockée qu'une fois (déduplication par hash).
- Un fichier n'est supprimé que quand plus aucune version ne le référence.

**Politique de rétention**

- Réglable au niveau du compte, et surchargeable par jeu.
- Stockée en JSON : `{"mode":"all"}`, `{"mode":"last_n","n":10}`, `{"mode":"days","n":30}`, `{"mode":"smart"}`. Valeur par défaut d'un compte : `smart`. Au niveau d'un jeu, `null` signifie « hérite du compte ».
- Modes :
  - `all` : tout garder.
  - `last_n` : les N versions les plus récentes (selon `saved_at`).
  - `days` : les versions dont `saved_at` date de moins de N jours.
  - `smart` : tout ce qui a moins de 7 jours ; entre 7 et 30 jours, la plus récente de chaque jour UTC ; au-delà de 30 jours, la plus récente de chaque semaine ISO (UTC).
- Les calculs se font sur `saved_at` (après correction d'horloge, voir « Protocole de synchronisation »).
- Ne supprime jamais la version active ni une version épinglée (`pinned`) : l'ensemble conservé est celui que désigne le mode, auquel s'ajoutent toujours la version active et les versions épinglées.
- Appliquée par une tâche périodique du serveur, pas au moment de l'envoi (intervalle réglable, 1 heure par défaut). Les blobs qui ne sont plus référencés sont supprimés dans la même passe.
- Une version peut aussi être supprimée à la main depuis le site (bouton « Supprimer » de l'historique), avec les mêmes protections : jamais la version active ni une version épinglée. Son fichier part à la passe suivante s'il n'est plus référencé. Les versions qui la désignaient comme `base_version_id` gardent cet identifiant.

## Identification des jeux

Un jeu est identifié par le code de 4 caractères de l'en-tête de la ROM ; le nom du fichier n'intervient jamais.

| Champ d'en-tête NDS | Position | Taille | Usage |
| --- | --- | --- | --- |
| Titre interne | 0x000 | 12 octets | Nom affiché par défaut |
| Code du jeu | 0x00C | 4 octets ASCII | Clé d'identification (ex. `IRBF`) |
| Code éditeur | 0x010 | 2 octets | Information |
| Type de console | 0x012 | 1 octet | Distingue DS, DS/DSi, DSi seul |
| Version de la ROM | 0x01E | 1 octet | Information |

Le 4e caractère du code donne la région (`F` France, `E` USA, `P` Europe, `J` Japon…) : deux régions donnent donc deux jeux distincts, ce qui est voulu car leurs saves ne sont pas toujours compatibles.

**Cas particuliers**

- ROM patchée ou traduite : elle garde en général le code d'origine et partage la save, ce qui est le comportement attendu.
- Hack qui change la structure de la save (rom hack Pokémon par exemple) : le client permet de forcer un identifiant personnalisé pour ce fichier ROM.
- Plusieurs ROMs locales avec le même identifiant (variantes patchées, traductions, hacks) : le client le signale dans la liste et demande, une fois par ROM, « partager la save » (même identifiant) ou « séparer » (identifiant forcé `x:` que l'utilisateur nomme). Tant qu'une ROM n'a pas de réponse, elle n'est pas synchronisée, pour qu'une variante n'écrase jamais la save d'une autre sans que l'utilisateur le sache. Les choix sont enregistrés par ROM (chemin du fichier, plus le nom intérieur pour une archive).
- Une ROM dans une archive est identifiée par l'en-tête du `.nds` décompressé ; l'identifiant `h:` est le SHA-1 du `.nds` décompressé, pas de l'archive.
- Homebrew ou ROM sans code valide (`####`, zéros) : repli sur un identifiant dérivé du hash SHA-1 de la ROM, préfixé `h:`.
- Le titre affiché peut être renommé dans l'interface web ; c'est purement cosmétique.

**Formats d'identifiant acceptés par le serveur** (tout autre format est refusé avec `400 invalid_request`)

| Format | Expression | Usage |
| --- | --- | --- |
| Code de cartouche | `^[A-Z0-9]{4}$` | Cas normal (ex. `IRBF`) ; la région est déduite du 4e caractère |
| Hash de ROM | `^h:[0-9a-f]{40}$` | Homebrew ou ROM sans code valide (SHA-1 de la ROM) |
| Identifiant forcé | `^x:[a-z0-9-]{1,32}$` | Identifiant personnalisé choisi par l'utilisateur (hack qui change la structure de la save) |

Dans les URL, l'identifiant est encodé normalement (`h%3A…` ou `h:…` sont tous deux acceptés).

## Format canonique et conversion

Le serveur ne stocke qu'un format : le contenu brut de la puce de save, à sa taille réelle. Chaque client convertit vers et depuis le format de son émulateur, ce qui permet de passer une save de melonDS à DeSmuME, à la 3DS ou à une flashcard sans manipulation.

**Taille réelle**

- Les puces DS ont des tailles fixes. Tailles de puce valides pour le serveur (union des tables de DeSmuME et de melonDS) : 512 o, 8 Kio, 32 Kio, 64 Kio, 128 Kio, 256 Kio, 512 Kio, 1 Mio, 2 Mio, 4 Mio, 8 Mio, 16 Mio, 32 Mio et 64 Mio (flash NAND de certains jeux).
- Une save n'est jamais coupée sur la seule base de son remplissage : une save de 512 Kio dont la seconde moitié est encore vierge est une save valide. Une coupe ne se fait que vers une taille de puce déjà connue.
- En entrée, le client retire seulement l'en-tête ou le pied ajouté par l'émulateur ; les règles de taille sont appliquées par le serveur.
- Taille de puce d'un jeu (`games.chip_size`) :
  - Si la base de tailles connaît le code du jeu, elle fait foi à la création du jeu. Cette base (`server/internal/chipdb/chipsizes.txt`, environ 6 700 jeux) est extraite de la liste de ROMs de melonDS (`src/ROMList.cpp`, GPL-3.0-or-later, compatible avec l'AGPL-3.0 par l'article 13 des deux licences). Elle n'a pas d'entrée 32 Kio : les jeux à FRAM 32 Kio y figurent à 64 Kio.
  - Sinon, la première save du jeu fixe `chip_size`.
- À l'envoi d'une save de taille différente de `chip_size` :
  - plus grande, et l'excédent n'est que du remplissage (tout 0xFF ou tout 0x00) : elle est coupée à `chip_size` ;
  - plus petite, et l'excédent de la version active n'est que du remplissage : `chip_size` prend la nouvelle taille et l'envoi est accepté. Si le jeu n'a pas encore de version active (taille issue de la base), l'envoi est accepté de la même façon, puisque rien ne peut être perdu, mais seulement si la nouvelle taille est une taille de puce valide (sinon `409 size_mismatch`) ; la réduction est tracée comme les autres ;
  - dans tous les autres cas : `409 size_mismatch` ; `X-Force-Size` reste possible depuis le site et fixe `chip_size` à la nouvelle taille.
- Chaque coupe ou changement de `chip_size` est tracé sur la version (`size_event` : `trimmed`, `shrunk` ou `forced` ; `size_event_from` : taille reçue pour une coupe, ancienne `chip_size` sinon) et affiché dans l'historique du site.
- En sortie : on complète avec 0xFF quand le profil cible impose une taille minimale, sans jamais couper. Profil `flashcard` : taille exportée = max(512 Kio, `chip_size`) ; une save plus grande sort à sa taille réelle.
- Exemple : une DSTT envoie une save de 64 Kio complétée à 512 Kio, `chip_size` vaut 512 Kio ; melonDS envoie ensuite la save de 64 Kio, l'excédent de la version active n'est que du remplissage, `chip_size` passe à 64 Kio ; les envois suivants de la DSTT sont coupés à 64 Kio.

**Profils de conversion**

| Cible | Fichier | Conversion | Statut |
| --- | --- | --- | --- |
| melonDS (standalone) | `<rom>.sav` à côté de la ROM ou dans le dossier configuré | Aucune (brut) | Confirmé |
| DeSmuME | `<rom>.dsv` dans son dossier Battery (détail ci-dessous) | Retirer ou ajouter le pied de fichier DeSmuME (122 octets, commence par `\|<--Snip above here`, détail ci-dessous) | Confirmé |
| melonDS DS (RetroArch) | `<rom>.srm` dans le dossier des saves de RetroArch (détail ci-dessous) | Aucune : tampon SRAM brut (`retro_get_memory_data`, `src/libretro/sram.cpp` de melonds-ds) | Confirmé par un aller-retour réel sous Windows (progression identique dans melonDS) |
| DraStic (Android) | `<rom>.dsv` dans `DraStic/backup/` | Brut, ou brut suivi du pied DeSmuME (sources contradictoires, voir `docs/research/android.md`) | À vérifier |
| nds-bootstrap / TWiLight Menu++ (3DS) | `<rom>.sav` (`.sav1` à `.sav9` selon l'emplacement de save du jeu) dans le sous-dossier `saves/` du dossier de la ROM, à côté de la ROM ou dans `sd:/_nds/TWiLightMenu/saves/` selon `SAVE_LOCATION` (détail ci-dessous) | Brut (profil `twilight`) ; TWiLight Menu++ complète lui-même le fichier avec des 0x00 jusqu'à la taille de sa base au lancement, sans jamais le couper | À vérifier par un aller-retour réel |
| Flashcard (DSTT, R4…) | `.sav` à côté de la ROM | Brut, complété avec 0xFF jusqu'à max(512 Kio, `chip_size`), jamais coupé (profil `flashcard`) | À vérifier par modèle |

Chaque profil est un petit fichier déclaratif en JSON (`profiles/<id>.json` : chemin, extension, en-tête/pied, règle de taille ; le JSON reste simple à lire en C sur 3DS), partagé entre le client Flutter et le homebrew 3DS, pour qu'un contributeur puisse ajouter un émulateur sans toucher au code. Les profils marqués « à vérifier » doivent être validés par des tests aller-retour avant la v1.

Côté serveur, les conversions nécessaires à l'import/export du site (brut, DeSmuME et flashcard en phase 1) sont codées en Go : `go:embed` ne peut pas lire `profiles/`, qui est hors du module. Un test vérifie que le code Go et les fichiers de `profiles/` restent cohérents.

**Dossier Battery de DeSmuME** (vérifié sur `desmume/src/path.cpp` et le frontend Cocoa)

- Linux (frontend GTK) : toujours `g_get_user_config_dir()/desmume`, soit `~/.config/desmume/` (ou `$XDG_CONFIG_HOME/desmume/`), et `~/.var/app/org.desmume.DeSmuME/config/desmume/` pour le Flatpak ; le réglage n'est pas modifiable sous Linux.
- Windows : clé `[PathSettings] Battery` du `desmume.ini` placé à côté de l'exécutable (UTF-16 avec BOM) ; par défaut `.\Battery` ; un chemin non absolu est résolu depuis le dossier de l'exécutable.
- macOS : `~/Library/Application Support/DeSmuME/<version de l'appli>/Battery`. La version dépend de l'appli installée : le client prend ce dossier s'il n'en existe qu'un, sinon il demande à l'utilisateur de le choisir.
- Nom : nom du fichier ROM sans son extension, où `" < > |`, les caractères de contrôle (et `/` sous Windows) sont remplacés par `*`, suivi de `.dsv`.
- Le Flatpak `org.desmume.DeSmuME` n'a aucun accès aux fichiers par défaut : le client propose `flatpak override --user --filesystem=<dossier>:ro org.desmume.DeSmuME` pour chaque dossier de ROMs.

**Dossier des saves de RetroArch (melonDS DS)** (vérifié sur `runloop.c` et `configuration.c` de RetroArch)

- `retroarch.cfg` est cherché comme le fait RetroArch : `$XDG_CONFIG_HOME/retroarch/retroarch.cfg` puis `~/.retroarch.cfg` sous Linux (`~/.var/app/org.libretro.RetroArch/config/retroarch/` pour le Flatpak) ; à côté de `retroarch.exe` puis dans `%APPDATA%` sous Windows ; `~/Library/Application Support/RetroArch/config/` sous macOS. Les surcharges `config/melonDS DS/` (cœur, dossier du jeu, jeu) s'appliquent dans cet ordre.
- Dossier : `savefile_directory` (`~` = dossier personnel, `:` = dossier de l'exécutable, `default` = dossier par défaut de RetroArch : `saves` à côté de l'exécutable sous Windows, `~/Library/Application Support/RetroArch/saves` sous macOS, le dossier de la ROM sous Linux). Vide, ou si `savefiles_in_content_dir` est actif : le dossier de la ROM. Puis le nom du dossier de la ROM si `sort_savefiles_by_content_enable`, puis `melonDS DS` (nom de bibliothèque du cœur) si `sort_savefiles_enable`.
- Nom : nom de la ROM sans son extension, suivi de `.srm`.
- La taille du `.srm` vient de la base de ROMs de melonDS (pas de 32 Kio : 64 Kio pour les jeux à FRAM 32 Kio) ; les règles de taille du serveur l'absorbent.
- Lancement : `retroarch -L <cœur> <rom>` (cœur `melondsds_libretro.so`, `.dll` ou `.dylib` dans `libretro_directory`, sinon le dossier `cores` de RetroArch).

**Saves de TWiLight Menu++ et nds-bootstrap (3DS)** (vérifié sur `title/arm9/source/main.cpp`, `twlmenusettings.cpp` et `pergamesettings.cpp` de TWiLight Menu++, `my_fat.c` de nds-bootstrap)

- Dossier : `[SRLOADER] SAVE_LOCATION` de `sd:/_nds/TWiLightMenu/settings.ini` : `0` (défaut) sous-dossier `saves/` du dossier de la ROM, `1` à côté de la ROM, `2` `sd:/_nds/TWiLightMenu/saves/`.
- Nom : nom du fichier ROM avec son extension remplacée par `.sav`, ou `.sav1` à `.sav9` selon `[GAMESETTINGS] SAVE_NUMBER` de `sd:/_nds/TWiLightMenu/gamesettings/<fichier ROM>.ini` (ignoré avec `SAVE_LOCATION=1`). Seul l'emplacement actif est synchronisé ; un changement d'emplacement est traité comme un changement de fichier de save (même avertissement qu'un changement d'émulateur sur PC).
- Taille : au lancement, TWiLight Menu++ crée la save ou l'agrandit jusqu'à la taille de sa propre base de ROMs (512 Kio pour un jeu inconnu), avec des 0x00. Le client écrit la save à sa taille réelle ; le remplissage ajouté ensuite est coupé par le serveur (même contenu que la version active : aucune version créée).
- Date : nds-bootstrap écrit les secteurs de la save directement sur la carte SD sans mettre à jour l'entrée de répertoire FAT : la date de modification du fichier ne change pas pendant la partie et n'est pas utilisée (voir « 3DS » dans le protocole).
- Le forwarder NTR (utilisé par YANBF) applique les mêmes règles avec ses propres réglages : `[NTR-FORWARDER] SAVE_LOCATION` de `sd:/_nds/ntr_forwarder.ini` et `sd:/_nds/ntr-forwarder/gamesettings/`. Les saves DSiWare (`.pub`, `.prv`) ne sont pas synchronisées.

**Pied de fichier DeSmuME** (vérifié sur `desmume/src/mc.cpp` et sur des fichiers `.dsv` réels)

| Décalage depuis la fin des données | Taille | Contenu |
| --- | --- | --- |
| 0 | 82 octets | Texte ASCII `\|<--Snip above here to create a raw sav by excluding this DeSmuME savedata footer:` |
| 82 | 4 octets LE | `size` : taille des données réellement écrites |
| 86 | 4 octets LE | `padSize` : taille des données dans le fichier (= taille du fichier − 122) |
| 90 | 4 octets LE | `type` : index dans la table `save_types` de DeSmuME (peut valoir 0 = autodétection) |
| 94 | 4 octets LE | `addr_size` : 1 (512 o), 2 (8 à 64 Kio), 3 (128 Kio et plus) |
| 98 | 4 octets LE | `mem_size` : taille de la mémoire de save |
| 102 | 4 octets LE | `version` : toujours 0 |
| 106 | 16 octets | Cookie `\|-DESMUME SAVE-\|` |

- Import : le fichier est reconnu au cookie final et à `version = 0` ; on vérifie que `padSize` = taille du fichier − 122, puis on garde les `padSize` premiers octets. `type` n'est pas utilisé.
- Export : données brutes, puis pied avec `size = padSize = mem_size =` taille brute, `type` = index DeSmuME de cette taille (0 si inconnue), `addr_size` selon la taille, `version = 0`.

## Protocole de synchronisation

Le client tire la save active avant de lancer le jeu, envoie chaque nouvelle save pendant la partie, puis fait un dernier envoi à la fermeture. Quand deux appareils ont joué sans se synchroniser (divergence), rien n'est envoyé ni écrasé avant que l'utilisateur ait choisi la save à garder ; l'autre reste dans l'historique.

**État local par fichier de save** (stocké par le client)

L'état est tenu par fichier de save, pas par jeu : plusieurs ROMs peuvent partager un identifiant de jeu, chacune avec son propre fichier de save. Chaque état est rattaché à l'identifiant de jeu avec lequel il a été synchronisé ; un état enregistré sous un autre identifiant (ROM séparée ou repartagée) est ignoré.

- `last_synced_version_id` : la version serveur sur laquelle la save locale est basée.
- `last_synced_hash` : le hash (SHA-256) du contenu brut local au moment de cette synchro. C'est le hash local qui est gardé, même si le serveur a coupé du remplissage et stocke un contenu de hash différent.
- File d'attente des envois en attente, persistée sur disque, avec une copie de chaque contenu en attente (la save peut encore changer avant l'envoi). Tout envoi passe par cette file : l'`upload_id` (UUID) est généré une fois, à la mise en file, et conservé jusqu'à l'acceptation, même après un redémarrage.
- À l'envoi d'un élément de la file, `X-Base-Version` est le `last_synced_version_id` courant de ce fichier de save : des envois mis en file hors ligne s'enchaînent donc sans créer de fausse divergence.
- Un envoi refusé définitivement par le serveur (ex. `409 size_mismatch`) est retiré de la file, et son contenu est conservé dans un dossier `failed` du client.
- Chaque élément de la file porte un mode : `auto` (envoi automatique), `local` ou `archive` (choix de l'utilisateur après une divergence, voir « Divergence »), et un indicateur `held` (envoi automatique retenu par une divergence). Le choix est donc conservé après un redémarrage ou une coupure.

**Avant le lancement**

1. Le client vide d'abord sa file d'attente si le serveur est joignable.
2. Il demande la version active du jeu (`GET /games/{code}/active`).
3. Si la save locale n'a pas changé depuis la dernière synchro et que le serveur a une version plus récente : il la télécharge, la convertit et l'écrit (l'ancienne copie locale est gardée dans un dossier `.backup` à côté de la save ; les N dernières copies sont gardées par save, 10 par défaut, nombre réglable).
4. Si la save locale a changé hors synchro (partie hors ligne) :
   - si son contenu est celui de la version active (après les règles de taille, voir « Divergence »), rien n'est envoyé et l'état local passe sur cette version ;
   - si la version active est celle de la dernière synchro de ce fichier : il l'envoie d'abord, puis télécharge la version active si elle a changé ;
   - sinon, c'est une divergence : il demande à l'utilisateur quelle save garder avant tout envoi ou téléchargement.
5. Il lance l'émulateur.

**Pendant la partie**

- Le client surveille le fichier de save (inotify, FSEvents, ReadDirectoryChangesW ; scrutation toutes les 5 s sur Android).
- Après 5 s sans nouvelle écriture, si le hash a changé, il envoie la save : chaque sauvegarde en jeu devient une version sur le serveur.

**À la fermeture**

- Quand le processus de l'émulateur se termine, le client relit le fichier et envoie la save si le hash a changé.

**Règle « la plus récente gagne »**

- Chaque envoi porte `saved_at` (date de modification du fichier sur l'appareil) et `base_version_id`.
- Sans en-tête `X-Activate`, le serveur crée toujours une nouvelle version ; il la rend active si son `saved_at` est strictement postérieur à celui de la version active (en cas d'égalité, la version active reste en place). La première save d'un jeu devient toujours active.
- Si `base_version_id` n'est pas la version active, il y a eu divergence : le serveur l'enregistre (`conflict = true` sur la nouvelle version). L'historique du site affiche, sur chaque version divergente, la version dont elle partait (ou « aucune »), et une bannière sur la page du jeu propose d'activer l'autre version. Un `X-Base-Version` vide alors que le jeu a déjà une version active compte aussi comme une divergence.
- Les clients à jour n'envoient plus une divergence sans le choix de l'utilisateur (voir « Divergence ») ; la règle s'applique donc aux envois sans divergence, aux envois des anciens clients, à l'import du site, et à un autre appareil qui envoie entre la vérification et l'envoi.

**Divergence**

- Définition, côté client : la save locale a changé depuis la dernière synchro, le serveur a une version active, celle-ci n'est pas `last_synced_version_id` de ce fichier (ou le fichier n'a jamais été synchronisé, par exemple sur un nouvel appareil), et son contenu est différent.
- Comparaison du contenu : avec les mêmes règles de taille que le serveur (« Taille réelle »), avec la taille de puce donnée par `GET /games/{code}/active` : une save plus grande que la taille de puce et dont l'excédent n'est que du remplissage est comparée une fois coupée (TWiLight Menu++ complète avec des 0x00, une flashcard avec des 0xFF) ; une save plus petite est identique à une version active dont l'excédent n'est que du remplissage (FRAM de 32 Kio vue à 64 Kio), ce qui demande de télécharger la version active, seulement dans ce cas. Les deux clients appliquent la même règle (`size_rule.dart`, `3ds/core/size_rule.c`).
- Tant que l'utilisateur n'a pas choisi, rien n'est envoyé ni écrasé ; il peut reporter (« Plus tard ») et la question revient à la synchro suivante.
- Choix :
  - « Envoyer ma save locale » : envoi avec `X-Activate: true`, la save devient active quelle que soit sa date ;
  - « Prendre celle du serveur » : la save locale est envoyée avec `X-Activate: false` (version non active, visible et restaurable sur le site), puis la version active est téléchargée ; la save locale est aussi copiée dans `.backup`.
- Au lancement d'un jeu (PC et 3DS), la question est posée avant le lancement ; « Plus tard » annule le lancement.
- Envois automatiques (PC : arrière-plan et pendant une partie ; 3DS : file d'attente remplie hors ligne) : avant chaque envoi en mode `auto`, le client vérifie la version active ; un envoi divergent n'est pas envoyé mais retenu dans la file (`held`), avec ceux qui le suivent pour la même save. Sur PC, l'état du jeu devient « choix à faire », une bannière propose le choix et une notification « Choix à faire pour <jeu> » est affichée une fois ; un clic dessus ouvre la boîte de dialogue. « Prendre celle du serveur » est refusé tant que ce jeu tourne depuis RomSync.
- Un envoi fait juste après un téléchargement part de la version active et n'est jamais divergent (tests de bout en bout des deux clients).
- Horloges décalées : le serveur compare `saved_at` à son heure de réception.
  - Si `saved_at` dépasse l'heure de réception de plus de 5 minutes, il est ramené à l'heure de réception ; la valeur d'origine est conservée dans `saved_at_reported`, et `devices.clock_skew_at` est renseigné. Sans cette correction, une save datée dans le futur resterait active et bloquerait toutes les saves suivantes.
  - Si `saved_at` est antérieur à l'heure de réception de plus de 5 minutes, ce n'est pas forcément une erreur (envoi différé depuis la file d'attente, 3DS) : la valeur est conservée telle quelle.
  - Une horloge en retard ne peut donc pas être corrigée par le serveur : c'est au client de le faire. Le homebrew 3DS, dont l'horloge est souvent mal réglée, corrige lui-même `saved_at` avec l'en-tête `Date` du serveur (voir « 3DS »). Les dates sont à la seconde : deux envois de la même seconde sont à égalité, et la version active reste en place.

**Hors ligne**

- Le jeu se lance quand même, avec un avertissement.
- Les envois sont mis en file d'attente et partent dès que le serveur répond.

**Idempotence**

- Chaque envoi porte un identifiant unique généré par le client (`upload_id`, 1 à 64 caractères `[A-Za-z0-9_-]`, un UUID est recommandé) ; un renvoi après une coupure ne crée pas de doublon : le serveur renvoie exactement la réponse d'origine (même version, même statut).
- Une save au même hash que la version active est ignorée (réponse `200`, aucune version créée, `created: false`).
- Une version créée donne une réponse `201`.

**3DS**

- L'appli ne tourne pas pendant le jeu ; à chaque démarrage, elle vide sa file d'attente, puis applique « Avant le lancement » (étapes 1 à 4) à chaque jeu : envoi des saves dont le hash diffère de `last_synced_hash`, puis téléchargement des versions plus récentes (avec copie `.backup`).
- Une divergence ouvre un écran de choix : A envoie la save locale, Y prend celle du serveur, B reporte (rien n'est envoyé ni écrasé, la question revient au prochain démarrage, et le jeu ne se lance pas). Après un changement d'emplacement `.savN`, « l'envoyer quand même » vaut le choix de la save locale et n'est pas redemandé.
- Un changement se détecte uniquement par le hash, la date du fichier n'étant pas fiable. `saved_at` est l'heure à laquelle l'appli voit le nouveau contenu pour la première fois, corrigée de l'écart entre l'horloge de la console et l'en-tête `Date` des réponses du serveur (mesuré à chaque réponse, gardé dans l'état local pour les envois hors ligne). Il faut donc ouvrir l'appli juste après avoir joué.
- Dès qu'un jeu trouve le serveur injoignable, les jeux suivants du même passage sont seulement mis en file d'attente, sans attendre un délai réseau par jeu ; sans Wi-Fi, aucun appel réseau n'est tenté.

## Authentification

Les humains se connectent au site avec identifiant et mot de passe ; les appareils n'ont jamais le mot de passe et utilisent un jeton obtenu par code d'appairage.

**Comptes**

- Premier démarrage : le site affiche un écran de création du compte admin ; il disparaît ensuite. La création ouvre directement une session.
- Identifiant : 1 à 32 caractères parmi lettres, chiffres, `_`, `.` et `-` (insensible à la casse) ; mot de passe : 8 à 256 caractères.
- L'admin génère des liens d'invitation à usage unique (7 jours) ; la personne invitée choisit son identifiant et son mot de passe.
- Mots de passe hachés avec Argon2id ; session web par cookie `HttpOnly`, `SameSite=Strict`, valable 30 jours et prolongée à chaque utilisation.
- Accepter une invitation ouvre directement une session pour le nouveau compte.
- L'admin peut désactiver un compte et réinitialiser un mot de passe, mais ne voit pas les saves des autres dans l'interface. Désactiver un compte ferme ses sessions ; ses appareils sont refusés tant qu'il est désactivé. L'admin ne peut pas se désactiver lui-même.

**Appairage d'un appareil**

1. Sur le site, l'utilisateur clique « Ajouter un appareil » : un code de 8 caractères s'affiche, valable 10 minutes (alphabet sans caractères ambigus, ex. `K7QM-4XPA`).
2. Sur l'appareil, il saisit l'adresse du serveur et ce code, plus un nom (« Fedora bureau », « 3DS »). La plateforme envoyée est l'une de `linux`, `macos`, `windows`, `android`, `3ds`, `other`.
3. L'appareil appelle `POST /pair` et reçoit un jeton aléatoire de 256 bits, qu'il conserve localement ; le serveur n'en garde que le hash.
4. Toutes les requêtes de l'appareil portent ensuite `Authorization: Bearer <jeton>`.

**Sécurité**

- Jetons révocables depuis la liste des appareils ; `last_seen_at` aide à repérer un appareil oublié.
- Sur Windows, le jeton est rangé dans le Gestionnaire d'identifiants (identifiant générique « RomSync », écrit par `CredWriteW`). Sur macOS, dans le trousseau « login » (l'appli n'est pas signée : macOS redemande l'accès au trousseau après chaque mise à jour, et l'appli est distribuée sans App Sandbox pour pouvoir lancer les émulateurs et lire les dossiers de ROMs). Sous Linux, le jeton est rangé dans le trousseau du système (API Secret Service via libsecret : GNOME Keyring, KWallet, KeePassXC…). Si aucun trousseau ne répond (session Hyprland sans Secret Service, par exemple), l'appairage est refusé par défaut avec un message clair ; l'utilisateur peut choisir explicitement de stocker le jeton dans un fichier (permissions 0600, avertissement affiché dans l'appli). Le jeton n'est jamais stocké en clair sans ce choix.
- Limitation de débit sur la connexion, l'appairage, le premier démarrage et l'acceptation d'invitation (5 essais par minute et par IP).
- Adresse IP du client : par défaut, l'adresse de la connexion TCP. `X-Forwarded-For` n'est lu que si la connexion vient d'une adresse listée dans `ROMSYNC_TRUSTED_PROXIES` (vide par défaut ; ex. `127.0.0.1` derrière `tailscale serve`).
- Sur 3DS, le jeton est stocké en clair sur la carte SD (`sd:/3ds/romsync/token.txt`) : c'est documenté, et un jeton volé se révoque sans changer de mot de passe.

## API REST

Toutes les routes sont préfixées `/api/v1`, échangent du JSON (sauf le contenu brut des saves en `application/octet-stream`) et sont décrites dans un fichier OpenAPI versionné dans le dépôt.

| Méthode | Route | Auth | Rôle |
| --- | --- | --- | --- |
| GET | `/setup` | aucune | Indique si le premier démarrage reste à faire (`{"needed": true}`) |
| POST | `/setup` | aucune | Crée le compte admin (seulement si aucun compte n'existe) |
| POST | `/auth/login` | aucune | Ouvre une session web |
| POST | `/auth/logout` | session | Ferme la session |
| GET | `/me` | session ou jeton | Utilisateur courant (et appareil courant pour un jeton) |
| PATCH | `/me` | session | Change la rétention du compte ou le mot de passe (mot de passe actuel requis) |
| GET | `/users` | admin | Liste les comptes |
| PATCH | `/users/{id}` | admin | Désactive/réactive un compte, réinitialise son mot de passe |
| GET | `/invites` | admin | Liste les invitations (en cours, utilisées, expirées) |
| POST | `/invites` | admin | Crée un lien d'invitation |
| POST | `/invites/{token}/accept` | aucune | Crée un compte depuis une invitation et ouvre une session |
| POST | `/pair-codes` | session | Génère un code d'appairage |
| POST | `/pair` | aucune | Échange un code contre un jeton d'appareil |
| GET | `/devices` | session | Liste les appareils du compte |
| DELETE | `/devices/{id}` | session | Révoque un appareil |
| GET | `/games` | session ou jeton | Liste les jeux et leur version active |
| PATCH | `/games/{code}` | session | Renomme le jeu, change sa rétention |
| GET | `/games/{code}/active` | session ou jeton | Métadonnées de la version active (id, hash, taille, saved\_at) et `chip_size` du jeu, pour comparer une save locale après les règles de taille |
| GET | `/games/{code}/versions` | session ou jeton | Historique paginé |
| POST | `/games/{code}/versions` | session ou jeton | Envoie une save (corps brut + en-têtes) |
| GET | `/versions/{id}/content` | session ou jeton | Télécharge le contenu brut |
| POST | `/versions/{id}/activate` | session | Fait d'une ancienne version la version active |
| PATCH | `/versions/{id}` | session | Épingle ou annote une version |
| DELETE | `/versions/{id}` | session | Supprime une version de l'historique (refusé, 409 `conflict`, pour la version active ou une version épinglée) |
| GET | `/versions/{id}/export?profile=desmume` | session | Export converti, pour l'import/export manuel |
| GET | `/server` | aucune | Version du serveur, `api_level` et `min_client_version` (voir « Compatibilité ») |
| GET | `/updates` | session ou jeton | Dernière release connue du relais (bannière du site) |
| GET | `/updates/{platform}` | session ou jeton | Dernier client d'une plateforme (`linux-x64`, `linux-arm64`, `macos`, `windows-x64`, `3ds`) avec `SHA256SUMS` et sa signature |
| GET | `/updates/files/{version}/{name}` | session ou jeton | Un fichier de la dernière release, depuis le cache du serveur |

**Envoi d'une save** — `POST /games/{code}/versions`

- Corps : contenu brut canonique.
- En-têtes : `X-Upload-Id`, `X-Saved-At` (ISO 8601), `X-Base-Version` (vide si première save), `X-Emulator`, `X-Content-SHA256`, `X-Game-Title` (optionnel, pour un jeu inconnu ; encodé en pourcentage, car les navigateurs n'envoient que des en-têtes Latin-1).
- En-tête optionnel `X-Activate` : le choix de l'utilisateur après une divergence (voir « Protocole de synchronisation »). `true` : la version devient active quelle que soit sa date (« Envoyer ma save locale ») ; `false` : elle est seulement archivée, comme version non active (« Prendre celle du serveur ») ; absent ou vide : la plus récente gagne. La première version d'un jeu est toujours active.
- En-tête optionnel `X-Force-Size: true` : accepte une taille que les règles de « Taille réelle » refusent, et en fait la nouvelle taille de puce du jeu. Accepté seulement avec une session web (refusé avec `403 forbidden` pour un jeton d'appareil).
- Paramètre optionnel `?profile=desmume` : le corps est un fichier au format du profil (ex. `.dsv`), converti en brut par le serveur avant tout traitement ; `X-Content-SHA256` porte alors sur le fichier envoyé. Sans paramètre, `profile=raw`.
- Réponse : `{"version": {...}, "created": bool, "active": bool, "conflict": bool}` ; `201` si une version a été créée, `200` sinon.
- Le serveur vérifie le hash annoncé et crée le jeu s'il n'existe pas encore.

**Pagination** — `GET /games/{code}/versions?limit=50&before=<id>` : versions triées de la plus récente à la plus ancienne (`saved_at`, puis `id`), `limit` entre 1 et 200 (50 par défaut). La réponse contient `next_before`, à repasser en `before` pour la page suivante, ou `null` s'il n'y en a plus.

**Erreurs** — format unique `{"error": {"code": "...", "message": "..."}}`

| Code HTTP | `code` | Cas |
| --- | --- | --- |
| 400 | `invalid_request` | Corps, paramètre ou en-tête invalide (identifiant de jeu mal formé, date illisible…) |
| 400 | `hash_mismatch` | Le contenu ne correspond pas à `X-Content-SHA256` |
| 401 | `unauthorized` | Jeton absent, révoqué ou session expirée ; identifiants incorrects ; compte désactivé |
| 403 | `forbidden` | Authentifié mais pas autorisé (route admin, `X-Force-Size` avec un jeton…) |
| 404 | `not_found` | Jeu, version, appareil, invitation ou compte inconnus pour ce compte |
| 409 | `already_setup` | `POST /setup` alors qu'un compte existe déjà |
| 409 | `size_mismatch` | Taille différente de la taille de puce connue du jeu |
| 409 | `conflict` | Contrainte d'unicité (identifiant déjà pris…) |
| 410 | `expired` | Invitation ou code d'appairage expiré ou déjà utilisé |
| 413 | `too_large` | Fichier au-delà de la limite (16 Mio par défaut) |
| 429 | `rate_limited` | Trop de tentatives de connexion, d'appairage, de premier démarrage ou d'acceptation d'invitation |
| 500 | `internal` | Erreur inattendue du serveur |

**Configuration du serveur** (variables d'environnement)

| Variable | Défaut | Rôle |
| --- | --- | --- |
| `ROMSYNC_PORT` | `8080` | Port d'écoute HTTP |
| `ROMSYNC_DATA_DIR` | `/data` | Dossier de la base SQLite et des blobs |
| `ROMSYNC_MAX_UPLOAD` | `16777216` | Taille maximale d'un envoi, en octets (16 Mio) |
| `ROMSYNC_TRUSTED_PROXIES` | vide | Adresses ou réseaux CIDR dont on accepte `X-Forwarded-For`, séparés par des virgules |
| `ROMSYNC_RETENTION_INTERVAL` | `1h` | Intervalle de la tâche de rétention (durée Go) |
| `ROMSYNC_UPDATES` | `on` | Relais des mises à jour vers les applis (`off` le désactive : pas de mise à jour des applis, pas de bannière sur le site) |
| `ROMSYNC_UPDATE_REPO` | `dadoux01/romsync` | Dépôt GitHub dont les releases sont relayées (un fork distribue les siennes, signées avec sa propre clé intégrée à ses applis) |
| `ROMSYNC_GITHUB_TOKEN` | vide | Jeton GitHub en lecture, seulement pour un dépôt privé |
| `ROMSYNC_UPDATE_INTERVAL` | `6h` | Intervalle de vérification de la dernière release (minimum 10 min) |

## Mises à jour et compatibilité

**Signature des releases**

- Chaque release GitHub contient `SHA256SUMS` (SHA-256 de chaque fichier) et `SHA256SUMS.sig`, signature Ed25519 de `SHA256SUMS` en base64. La clé privée n'est accessible qu'au job `sign` de `release.yml`, par l'environnement GitHub `release` réservé aux tags `v*` ; la clé publique est `keys/release-ed25519.pub`, intégrée aux applis (des tests vérifient que leurs copies sont identiques). Détails : `docs/releasing.md`.
- La vérification Ed25519 est stricte (RFC 8032, section 5.1.7) : une signature non canonique (S ≥ L) est refusée. Côté PC, `pinenacl` ne fait pas ce contrôle : `verifyEd25519` le fait avant de l'appeler. Les vecteurs de la RFC 8032 (section 7.1), une signature produite par openssl comme dans `release.yml`, et une liste commune de 72 cas (`testdata/ed25519/verdicts.json`) donnent les mêmes verdicts en Dart, en C (Monocypher) et avec openssl.
- Une mise à jour n'est acceptée que si la signature de `SHA256SUMS` est valide pour cette clé, puis si le SHA-256 du fichier téléchargé est celui de `SHA256SUMS`. Sinon elle est refusée et rien n'est installé.
- Jamais de rétrogradation : seule une version finale (sans suffixe `-rc…`) strictement plus récente est proposée. Une version de développement (`dev`, build local ou de CI) ne propose jamais de mise à jour.
- Les notes de chaque release commencent par l'ordre de mise à jour : serveur d'abord, puis les clients.

**Relais par le serveur**

- Le serveur ne se met pas à jour lui-même (c'est le rôle de Dockge ou de `docker compose pull`). Il interroge la dernière release finale de `ROMSYNC_UPDATE_REPO` toutes les 6 heures (sans jeton pour un dépôt public) et met ses fichiers en cache dans `/data/updates/` au premier téléchargement ; seuls les fichiers de la dernière release sont servis, et le cache des versions précédentes est supprimé.
- Les applis ne parlent qu'à leur serveur : `GET /updates/{platform}`, puis les trois fichiers. Le relais n'a pas besoin d'être de confiance, puisque les applis vérifient la signature ; il évite le HTTPS vers GitHub sur 3DS (certificats, mbedtls) et un jeton GitHub dans les applis.
- Le site affiche à l'administrateur une bannière discrète quand une version plus récente que celle du serveur existe, avec le lien vers ses notes ; elle peut être masquée pour cette version.

**Appli PC**

- Vérification au démarrage puis toutes les 24 heures (réglage pour la désactiver), et bouton « Rechercher une mise à jour » dans les réglages.
- Une version disponible est annoncée (bannière, notification une fois par version) ; ses notes sont affichées, puis, sur accord, l'archive est téléchargée, vérifiée et extraite à côté de l'installation (`<installation>.new`, même système de fichiers).
- L'installation et le redémarrage n'ont lieu qu'après l'accord de l'utilisateur, et jamais pendant une partie ni avec des envois en attente (y compris retenus par une divergence) : la mise à jour attend, puis s'installe dès que c'est possible.
- Installation : l'installation devient `<installation>.old` et la nouvelle version prend sa place ; si la seconde étape échoue, l'ancienne est remise en place et continue de fonctionner. `<installation>.old` est supprimé au démarrage suivant de la nouvelle version. Linux : remplacement du dossier de l'archive ; macOS : remplacement du `.app` (un programme en cours d'exécution peut être renommé) ; Windows : petit programme séparé `romsync-updater.exe` (paquet `client/packages/romsync_updater`), copié hors des dossiers échangés, qui attend la fin de RomSync, échange les dossiers puis relance RomSync.
- Si le dossier d'installation n'est pas modifiable, l'appli le dit et propose l'installation manuelle.

**Homebrew 3DS**

- Vérification au démarrage (réglage pour la désactiver) et depuis les réglages ; notes de version, puis, sur accord, téléchargement du `.cia` par le relais, vérification de la signature et du hash (Ed25519 de Monocypher), et installation par le service AM, comme Universal-Updater. L'appli se ferme ensuite et se relance depuis le menu HOME.

**Compatibilité**

- `GET /server` (sans authentification) donne `version`, `api_level` et `min_client_version`. Un serveur sans cette route (avant 0.5.0) compte comme niveau 1.
- Niveaux : 2 = `X-Activate` (choix après une divergence), `chip_size` de `GET /games/{code}/active`, suppression d'une version, relais des mises à jour. Les clients 0.5.0 demandent le niveau 2.
- Serveur trop ancien : les applis l'affichent clairement (« mets d'abord à jour le serveur »), et le choix en cas de divergence n'est pas envoyé : il dépend de `X-Activate`, qu'un ancien serveur ignorerait en appliquant « la plus récente gagne ». Rien n'est envoyé ni écrasé, et les envois retenus restent en file.
- Application trop ancienne (version inférieure à `min_client_version`) : message « mets-la à jour ».

## Clients

Trois façons d'accéder aux saves, avec la même logique de synchro : l'appli Flutter, le homebrew 3DS, et l'import/export du site pour ce qui ne peut pas se connecter.

**Appli Flutter (Linux, macOS, Windows, Android)**

- Bibliothèque : l'utilisateur ajoute un ou plusieurs dossiers de ROMs ; l'appli lit l'en-tête de chaque `.nds` (y compris dans un `.zip`, lu directement, ou un `.7z`, lu avec le programme 7-Zip `7z`, `7zz` ou `7za` ; sans lui, l'appli affiche « installer 7zip ») et affiche les jeux avec l'état de leur save : à jour, à envoyer, à télécharger, hors ligne, choix requis (ROMs partageant un identifiant), choix à faire (divergence, voir le protocole), plus la mention « conflit résolu automatiquement ».
- Le client ne coupe jamais une save : il retire seulement l'en-tête ou le pied du profil de conversion, puis envoie le brut ; la normalisation de taille est faite par le serveur.
- Architecture : toute la logique hors interface (client API, en-têtes NDS, profils de conversion, état local, file d'attente, moteur de synchro, profils d'émulateurs) est dans un package Dart pur, `client/packages/romsync_core`, testable sans Flutter ; l'appli Flutter n'est qu'une interface. Les profils de conversion sont les fichiers `profiles/*.json`, copiés dans les ressources de l'appli au build (un test vérifie que les copies sont identiques).
- melonDS (phase 2) : installé en binaire ou en Flatpak (`net.kuribo64.melonDS`, lancé par `flatpak run`). Le dossier des saves est lu dans sa configuration (`SaveFilePath` de `melonDS.toml`, ou de l'ancien `melonDS.ini`, y compris sous `~/.var/app/net.kuribo64.melonDS/config/melonDS/` pour le Flatpak) : vide, la save est à côté de la ROM (à côté de l'archive pour une ROM dans un `.zip`/`.7z`), nommée comme la ROM avec l'extension `.sav`. L'utilisateur peut imposer un autre dossier. Pour le Flatpak, l'appli lit ses droits (`flatpak info --show-permissions`) et, si un dossier de ROMs ou de saves est hors d'atteinte, affiche la commande `flatpak override --user --filesystem=<dossier> net.kuribo64.melonDS`.
- Profils d'émulateurs : l'utilisateur choisit un émulateur par défaut et peut le changer par jeu (par identifiant de jeu : toutes les ROMs d'un même jeu suivent ce choix) ; chaque profil indique le chemin de l'exécutable (ou de l'appli `.app` sur macOS), le mode Flatpak sous Linux, les arguments de lancement, le dossier des saves et le profil de conversion. Émulateurs de la phase 3 : melonDS, DeSmuME et RetroArch avec le cœur melonDS DS.
- Changement d'émulateur pour un jeu : la save du nouvel émulateur n'a pas encore d'état local et suit donc la règle normale (envoyée si elle existe, sinon la version active est téléchargée). Si un fichier de save du nouvel émulateur existe sans avoir jamais été synchronisé par RomSync pour ce jeu (ancienne partie), l'appli prévient et propose de le mettre de côté dans `.backup` plutôt que de l'envoyer.
- ROMs en archive (`.zip`, `.7z`) : seul melonDS les lance dans cette phase ; avec DeSmuME ou RetroArch, la ROM est marquée « indisponible » avec la raison.
- Lancement sur PC : processus enfant suivi jusqu'à sa fin. Sur macOS, une `.app` est lancée par son exécutable interne (`Contents/MacOS`), sauf DeSmuME (appli Cocoa qui ignore les arguments) lancé par `open -W -n -a`. Sur Android : lancement par intent, puis détection du retour dans l'appli et scrutation du fichier.
- Lecture des saves : un fichier n'est lu que complet et stable (taille et date identiques avant, après et peu après la lecture) ; les erreurs de partage des émulateurs qui gardent la save ouverte (Windows) sont retentées. Un fichier lu à moitié n'est jamais envoyé. Surveillance par inotify (Linux), FSEvents (macOS) et ReadDirectoryChangesW (Windows).
- Android : accès aux dossiers des émulateurs via le sélecteur de dossiers du système (Storage Access Framework) ; les dossiers privés d'une appli ne sont pas accessibles et doivent être déplacés par l'utilisateur dans l'émulateur.
- Icône de barre système sur PC pour la surveillance des saves quand le jeu est lancé sans passer par l'appli : fermer la fenêtre garde l'appli dans la barre (réglable). En arrière-plan, l'appli ne fait qu'envoyer : chaque save modifiée est envoyée après 5 s sans écriture, sauf une save divergente, retenue jusqu'au choix de l'utilisateur (notification « Choix à faire pour <jeu> »). Elle ne télécharge jamais, car l'émulateur peut avoir la save ouverte ; une notification signale une save plus récente sur le serveur, avec le nom du jeu et l'appareil d'où elle vient (une fois par version), et elle sera téléchargée au prochain lancement depuis l'appli. Sous Linux, l'icône utilise StatusNotifierItem : KDE l'affiche, GNOME demande l'extension AppIndicator, Hyprland une barre compatible (waybar).

**Homebrew 3DS (C, devkitPro)**

- Architecture : un cœur en C99 portable (`3ds/core` : client API, JSON avec cJSON, SHA-1/SHA-256, en-tête NDS, profils, état local, file d'attente, décisions de synchro, réglages de TWiLight Menu++), sans libctru, compilé et testé sous Linux, y compris en bout en bout contre le vrai serveur ; ses décisions et ses cas de test reprennent ceux de `romsync_core`. Une fine couche 3DS (`3ds/app`, libctru) gère les écrans, le clavier, le réseau et le lancement. Distribué en `.cia` et `.3dsx` (détail dans `3ds/README.md`).
- Premier lancement : adresse du serveur, code d'appairage et nom de l'appareil saisis avec le clavier système (`platform=3ds`) ; puis choix d'un ou plusieurs dossiers de ROMs avec un petit navigateur de la carte SD (`sd:/roms/nds/` proposé s'il existe ; sous-dossiers inclus ou non, par dossier ; modifiables dans les réglages). Un dossier sans `.nds` est signalé. Les fichiers de l'appli sont dans `sd:/3ds/romsync/`.
- Interface en console texte sur les deux écrans : liste des jeux et état de leur save (avec la mention « conflit résolu automatiquement »), détails du jeu (identifiant, fichier et emplacement de save, dernière synchro, envois en attente), synchro d'un jeu ou de tous, choix « partager » ou « séparer » pour les ROMs qui partagent un identifiant.
- Au démarrage : envoi des saves modifiées depuis la dernière synchro, puis téléchargement des versions plus récentes (voir « 3DS » dans le protocole).
- Profils de conversion intégrés à l'appli (romfs), remplaçables par ceux de `sd:/3ds/romsync/profiles/`.
- Lancement d'un jeu (facultatif) : l'appli synchronise le jeu, écrit le chemin de la ROM dans `sd:/_nds/ntr-forwarder/path.txt`, puis saute vers le titre DSi `bootstrap.cia` de YANBF (`0004800546574452`), qui démarre le forwarder NTR puis nds-bootstrap, comme les forwarders de YANBF. Il faut installer `bootstrap.cia` et le pack de forwarders NTR ; sans eux, l'appli ne fait que la synchro et explique quoi installer. Le lancement est bloqué, avec la marche à suivre, si les réglages de save du forwarder (`SAVE_LOCATION`, emplacement du jeu) ne désignent pas le même fichier que ceux de TWiLight Menu++. À la fin de la partie, la console revient au menu HOME.
- Réseau via libcurl (portlib `3ds-curl` de devkitPro, le même code que celui testé sous Linux) ; le serveur doit être joignable par la 3DS, donc sur le réseau local (Tailscale n'existe pas sur 3DS).

**Import/export sur le site (DS + flashcard, dépannage)**

- Import : glisser un `.sav` ou `.dsv` ; le site détecte le format (cookie DeSmuME en fin de fichier) et l'envoie avec `?profile=desmume` le cas échéant. Le nom d'un fichier de save ne donne pas le code du jeu : l'utilisateur choisit un jeu existant ou saisit un code. En option, il peut désigner le `.nds` correspondant : le navigateur lit localement les 512 premiers octets pour en tirer le code et le titre, et la ROM n'est jamais envoyée.
- Export : télécharger la version active ou une ancienne version dans le format de la cible choisie (brut, DeSmuME, ou flashcard : brut complété à max(512 Kio, taille de puce), format à vérifier par modèle).

## Dépôt, roadmap et questions ouvertes

Un seul dépôt (monorepo) contient le serveur, le site, l'appli et le homebrew, pour que l'API et les profils de conversion restent alignés.

```
/
├── server/        # Go : API, stockage, rétention, binaire unique
├── web/           # interface web, compilée puis embarquée dans server/
├── client/        # appli Flutter (Linux, macOS, Windows, Android)
├── 3ds/           # homebrew 3DS en C (devkitPro)
├── profiles/      # profils de conversion déclaratifs, partagés
├── api/           # spécification OpenAPI
├── deploy/        # Dockerfile, docker-compose.yml d'exemple
└── docs/          # cette spécification, guides d'installation
```

- CI GitHub Actions : tests Go, build de l'image Docker, builds Flutter par plateforme, build du `.3dsx` et du `.cia`.
- Tests de conversion : un jeu de saves de référence (homebrew libres de droits) converties aller-retour pour chaque profil.

**Licence** : AGPL-3.0. Le code reste libre, et toute personne qui modifie RomSync et le propose en service hébergé doit publier ses modifications.

**Roadmap**

1. Serveur + site : comptes, invitations, versions, rétention, import/export manuel. Utilisable seul avec la DSTT.
2. Appli Flutter sur Linux : bibliothèque, lanceur melonDS, synchro complète. Premier usage réel sur Fedora.
3. Profils DeSmuME et melonDS DS ; builds macOS (Asahi : Linux ARM64) et Windows ; icône de barre système ; publication des versions (GitHub Releases, image `ghcr.io`).
4. Homebrew 3DS : synchro au démarrage, puis lancement via YANBF et nds-bootstrap (facultatif).
5. Android (en attente d'un testeur) : DraStic, melonDS Android, RetroArch avec melonDS DS, accès aux dossiers via le sélecteur système. Recherches déjà faites (ce qui est vérifié, ce qui reste incertain, sources) : `docs/research/android.md`.
6. iOS (à étudier, rien n'est codé) :
   - RetroArch iOS : son dossier est visible dans l'appli Fichiers ; à vérifier : emplacement des `.srm` et accès depuis une autre appli.
   - Delta : ses saves ne sont pas accessibles depuis une autre appli ; seulement l'import/export manuel d'une save par jeu, avec le site de RomSync.
   - Automatisation via Raccourcis : lire une save dans Fichiers et l'envoyer à l'API, ou télécharger la version active, sans appli à installer.
   - Installation d'une appli : compte développeur Apple payant, ou AltStore et identifiant Apple gratuit (signature à renouveler tous les 7 jours).

Version 0.5.0 (entre les phases 4 et 5) : choix en cas de divergence, mises à jour automatiques des applis (PC et 3DS) par le relais du serveur, releases signées. C'est la dernière installation manuelle des applis ; le serveur, lui, se met à jour par son image (Dockge).

**Questions ouvertes**

- ~~Framework du site~~ : tranché, Svelte 5 + Vite (sans SvelteKit), SPA compilée puis embarquée avec `go:embed`.
- Chiffrement des saves au repos, utile si le serveur est partagé avec d'autres personnes.
- Comportement par défaut des profils marqués « à vérifier » tant que les tests aller-retour ne sont pas faits.
