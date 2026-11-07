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
- 3DS : l'appli lance le jeu DS via nds-bootstrap et se ferme ; l'envoi de la save se fait donc au prochain démarrage de l'appli, pas à la fin de la partie.

## Architecture

Un seul binaire Go sert l'API et l'interface web ; tous les clients parlent à la même API REST, et le serveur ne contacte jamais les appareils.

&#91;embedded content: architecture · 4 types d'appareils, 1 serveur\]

Les trois applis appellent l'API directement ; le navigateur passe par le site, qui utilise la même API. La 3DS ne peut pas utiliser Tailscale et doit donc être sur le réseau local.

| Composant | Techno | Rôle |
| --- | --- | --- |
| Serveur | Go, SQLite, stockage fichiers | API, comptes, appareils, versions de saves, rétention |
| Interface web | SPA compilée et embarquée dans le binaire Go | Comptes, invitations, appairage, historique, restauration, import/export manuel |
| Client | Flutter (Linux, macOS, Windows, Android) | Scan des ROMs, lanceur d'émulateurs, conversion et synchro des saves |
| Homebrew 3DS | C, devkitPro (libctru) | Scan de la SD, synchro des saves, lancement via nds-bootstrap |

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
| `save_versions` | id, game\_id, blob\_hash, size, saved\_at, saved\_at\_reported, uploaded\_at, device\_id, emulator, base\_version\_id, upload\_id, is\_active, conflict, pinned, note | Une seule version active par jeu ; `upload_id` unique par compte ; `conflict` = divergence détectée à l'envoi |
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

- Les puces DS ont des tailles fixes : 512 o, 8 Kio, 64 Kio, 128 Kio, 256 Kio, 512 Kio, 1 Mio, 8 Mio et plus pour la flash NAND de certains jeux.
- En entrée : on retire tout en-tête ou pied ajouté par l'émulateur, puis on ramène le fichier à la taille de puce la plus proche si le surplus n'est que du remplissage (0xFF ou 0x00).
- En sortie : on complète avec 0xFF si l'émulateur ou la flashcard attend un fichier plus grand.
- Le serveur mémorise la taille de puce détectée pour chaque jeu et refuse une save d'une autre taille, sauf forçage depuis l'interface.

**Profils de conversion**

| Cible | Fichier | Conversion | Statut |
| --- | --- | --- | --- |
| melonDS (standalone) | `<rom>.sav` à côté de la ROM ou dans le dossier configuré | Aucune (brut) | Confirmé |
| DeSmuME | `<rom>.dsv` dans son dossier Battery | Retirer ou ajouter le pied de fichier DeSmuME (122 octets, commence par `\|<--Snip above here`, détail ci-dessous) | Confirmé |
| melonDS DS (RetroArch) | `<rom>.srm` dans le dossier saves de RetroArch | Aucune a priori | À vérifier |
| DraStic (Android) | `<rom>.dsv` dans `DraStic/backup/` | Aucune a priori | À vérifier |
| nds-bootstrap / TWiLight Menu++ (3DS) | `.sav` dans le sous-dossier `saves/` de la ROM | Brut, taille stricte | À vérifier |
| Flashcard (DSTT, R4…) | `.sav` à côté de la ROM | Brut, souvent complété à une taille fixe | À vérifier par modèle |

Chaque profil est un petit fichier déclaratif en JSON (`profiles/<id>.json` : chemin, extension, en-tête/pied, règle de taille ; le JSON reste simple à lire en C sur 3DS), partagé entre le client Flutter et le homebrew 3DS, pour qu'un contributeur puisse ajouter un émulateur sans toucher au code. Les profils marqués « à vérifier » doivent être validés par des tests aller-retour avant la v1.

Côté serveur, les conversions nécessaires à l'import/export du site (brut et DeSmuME en phase 1) sont codées en Go : `go:embed` ne peut pas lire `profiles/`, qui est hors du module. Un test vérifie que le code Go et les fichiers de `profiles/` restent cohérents.

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

Le client tire la save active avant de lancer le jeu, envoie chaque nouvelle save pendant la partie, puis fait un dernier envoi à la fermeture ; en cas de divergence, la save faite le plus récemment devient active et l'autre reste dans l'historique.

**État local par jeu** (stocké par le client)

- `last_synced_version_id` : la version serveur sur laquelle la save locale est basée.
- `last_synced_hash` : le hash de la save locale au moment de cette synchro.
- File d'attente des envois en attente, persistée sur disque.

**Avant le lancement**

1. Le client vide d'abord sa file d'attente si le serveur est joignable.
2. Il demande la version active du jeu (`GET /games/{code}/active`).
3. Si la save locale n'a pas changé depuis la dernière synchro et que le serveur a une version plus récente : il la télécharge, la convertit et l'écrit (l'ancienne copie locale est gardée dans un dossier `.backup`).
4. Si la save locale a changé hors synchro (partie hors ligne) : il l'envoie d'abord, et la règle « la plus récente gagne » s'applique côté serveur avant le téléchargement.
5. Il lance l'émulateur.

**Pendant la partie**

- Le client surveille le fichier de save (inotify, FSEvents, ReadDirectoryChangesW ; scrutation toutes les 5 s sur Android).
- Après 5 s sans nouvelle écriture, si le hash a changé, il envoie la save : chaque sauvegarde en jeu devient une version sur le serveur.

**À la fermeture**

- Quand le processus de l'émulateur se termine, le client relit le fichier et envoie la save si le hash a changé.

**Règle « la plus récente gagne »**

- Chaque envoi porte `saved_at` (date de modification du fichier sur l'appareil) et `base_version_id`.
- Le serveur crée toujours une nouvelle version ; il la rend active si son `saved_at` est strictement postérieur à celui de la version active (en cas d'égalité, la version active reste en place). La première save d'un jeu devient toujours active.
- Si `base_version_id` n'est pas la version active, il y a eu divergence : le serveur l'enregistre (`conflict = true` sur la nouvelle version) et l'interface web affiche « conflit résolu automatiquement », avec un bouton pour activer l'autre version. Un `X-Base-Version` vide alors que le jeu a déjà une version active compte aussi comme une divergence.
- Horloges décalées : le serveur compare `saved_at` à son heure de réception.
  - Si `saved_at` dépasse l'heure de réception de plus de 5 minutes, il est ramené à l'heure de réception ; la valeur d'origine est conservée dans `saved_at_reported`, et `devices.clock_skew_at` est renseigné. Sans cette correction, une save datée dans le futur resterait active et bloquerait toutes les saves suivantes.
  - Si `saved_at` est antérieur à l'heure de réception de plus de 5 minutes, ce n'est pas forcément une erreur (envoi différé depuis la file d'attente, 3DS) : la valeur est conservée telle quelle.

**Hors ligne**

- Le jeu se lance quand même, avec un avertissement.
- Les envois sont mis en file d'attente et partent dès que le serveur répond.

**Idempotence**

- Chaque envoi porte un identifiant unique généré par le client (`upload_id`, 1 à 64 caractères `[A-Za-z0-9_-]`, un UUID est recommandé) ; un renvoi après une coupure ne crée pas de doublon : le serveur renvoie exactement la réponse d'origine (même version, même statut).
- Une save au même hash que la version active est ignorée (réponse `200`, aucune version créée, `created: false`).
- Une version créée donne une réponse `201`.

**3DS**

- L'appli se ferme au lancement du jeu par nds-bootstrap ; au démarrage suivant, elle compare chaque save à `last_synced_hash` et envoie celles qui ont changé.

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
- Limitation de débit sur la connexion, l'appairage, le premier démarrage et l'acceptation d'invitation (5 essais par minute et par IP).
- Adresse IP du client : par défaut, l'adresse de la connexion TCP. `X-Forwarded-For` n'est lu que si la connexion vient d'une adresse listée dans `ROMSYNC_TRUSTED_PROXIES` (vide par défaut ; ex. `127.0.0.1` derrière `tailscale serve`).
- Sur 3DS, le jeton est stocké en clair sur la carte SD : c'est documenté, et un jeton volé se révoque sans changer de mot de passe.

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
| GET | `/games/{code}/active` | session ou jeton | Métadonnées de la version active (id, hash, taille, saved\_at) |
| GET | `/games/{code}/versions` | session ou jeton | Historique paginé |
| POST | `/games/{code}/versions` | session ou jeton | Envoie une save (corps brut + en-têtes) |
| GET | `/versions/{id}/content` | session ou jeton | Télécharge le contenu brut |
| POST | `/versions/{id}/activate` | session | Fait d'une ancienne version la version active |
| PATCH | `/versions/{id}` | session | Épingle ou annote une version |
| GET | `/versions/{id}/export?profile=desmume` | session | Export converti, pour l'import/export manuel |

**Envoi d'une save** — `POST /games/{code}/versions`

- Corps : contenu brut canonique.
- En-têtes : `X-Upload-Id`, `X-Saved-At` (ISO 8601), `X-Base-Version` (vide si première save), `X-Emulator`, `X-Content-SHA256`, `X-Game-Title` (optionnel, pour un jeu inconnu ; encodé en pourcentage, car les navigateurs n'envoient que des en-têtes Latin-1).
- En-tête optionnel `X-Force-Size: true` : accepte une taille différente de la taille de puce mémorisée et remplace celle-ci. Accepté seulement avec une session web (refusé avec `403 forbidden` pour un jeton d'appareil).
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

## Clients

Trois façons d'accéder aux saves, avec la même logique de synchro : l'appli Flutter, le homebrew 3DS, et l'import/export du site pour ce qui ne peut pas se connecter.

**Appli Flutter (Linux, macOS, Windows, Android)**

- Bibliothèque : l'utilisateur ajoute un ou plusieurs dossiers de ROMs ; l'appli lit l'en-tête de chaque `.nds` (y compris dans un `.zip` ou `.7z`) et affiche les jeux avec l'état de leur save : à jour, à envoyer, à télécharger, hors ligne.
- Profils d'émulateurs : l'utilisateur choisit un émulateur par défaut et peut le changer par jeu ; chaque profil indique le chemin de l'exécutable, les arguments de lancement et le profil de conversion.
- Lancement sur PC : processus enfant suivi jusqu'à sa fin. Sur Android : lancement par intent, puis détection du retour dans l'appli et scrutation du fichier.
- Android : accès aux dossiers des émulateurs via le sélecteur de dossiers du système (Storage Access Framework) ; les dossiers privés d'une appli ne sont pas accessibles et doivent être déplacés par l'utilisateur dans l'émulateur.
- Icône de barre système sur PC pour la surveillance des saves quand le jeu est lancé sans passer par l'appli.

**Homebrew 3DS (C, devkitPro)**

- Interface simple sur les deux écrans : liste des jeux DS trouvés sur la SD, état de chaque save, bouton de synchro.
- Au démarrage : envoi des saves modifiées depuis la dernière synchro, puis téléchargement des versions plus récentes.
- Lancement d'un jeu : écriture de la configuration de nds-bootstrap (chemin de la ROM et de la save) puis redémarrage dans nds-bootstrap, comme le fait TWiLight Menu++.
- Réseau via les services HTTP de la 3DS (`httpc`) ou libcurl ; le serveur doit être joignable par la 3DS, donc sur le réseau local (Tailscale n'existe pas sur 3DS).

**Import/export sur le site (DS + flashcard, dépannage)**

- Import : glisser un `.sav` ou `.dsv` ; le site détecte le format (cookie DeSmuME en fin de fichier) et l'envoie avec `?profile=desmume` le cas échéant. Le nom d'un fichier de save ne donne pas le code du jeu : l'utilisateur choisit un jeu existant ou saisit un code. En option, il peut désigner le `.nds` correspondant : le navigateur lit localement les 512 premiers octets pour en tirer le code et le titre, et la ROM n'est jamais envoyée.
- Export : télécharger la version active ou une ancienne version dans le format de la cible choisie (brut, DeSmuME ; flashcard quand son profil aura été vérifié).

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
3. Profils DeSmuME et melonDS DS ; builds macOS (Asahi : Linux ARM64) et Windows.
4. Android : DraStic, melonDS Android, accès aux dossiers via le sélecteur système.
5. Homebrew 3DS : synchro au démarrage, puis lancement via nds-bootstrap.

**Questions ouvertes**

- ~~Framework du site~~ : tranché, Svelte 5 + Vite (sans SvelteKit), SPA compilée puis embarquée avec `go:embed`.
- Chiffrement des saves au repos, utile si le serveur est partagé avec d'autres personnes.
- Comportement par défaut des profils marqués « à vérifier » tant que les tests aller-retour ne sont pas faits.
