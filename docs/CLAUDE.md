# RomSync — guide pour Claude Code

Synchronisation auto-hébergée des saves Nintendo DS : un serveur Go, un site
Svelte embarqué dans le binaire, un client Flutter (Linux, macOS, Windows),
et un homebrew 3DS (C). Les phases 1 à 4 de la roadmap sont livrées.

## Référence

- **`docs/SPEC.md` fait foi.** La lire (au moins les sections concernées) avant
  toute modification. Pour s'en écarter, demander d'abord à l'utilisateur.
- Signaler tout point ambigu ou faux de la spec au lieu de deviner.
- Toute décision prise pendant une phase est reportée dans `docs/SPEC.md`, dans
  le commit de docs de fin de phase.
- `api/openapi.yaml` décrit chaque route ; `TestOpenAPICoversRoutes` échoue si
  le router et la spec OpenAPI divergent.

## Méthode de travail

- Communiquer en français (accents compris) ; code, commentaires, README et
  CONTRIBUTING en anglais ; interfaces (site, appli) en français.
- Nouvelle phase : présenter un plan découpé en étapes et **attendre la
  validation** avant de coder.
- Un commit par étape, au format Conventional Commits (`feat(server): …`,
  `feat(core): …`, `feat(app): …`, `fix(…)`, `test(…)`, `ci: …`, `docs: …`),
  tests au vert avant chaque commit, et un résumé en 3 lignes à la fin de
  chaque étape (fait / reste).
- Ne pousser, ne créer de tag ou de release que sur demande explicite.
  L'utilisateur crée lui-même les tags `v*` quand la CI est verte.
- Vérifier dans les sources des émulateurs (melonDS, DeSmuME, RetroArch,
  melonDS DS) plutôt que supposer un format ou un chemin.

## Organisation du dépôt

```
server/                  Go : API (internal/api), règles de synchro et de taille
                         (internal/syncrule), rétention, conversions, blobs,
                         SQLite + migrations (internal/db/migrations), base de
                         tailles de puce (internal/chipdb, générée depuis melonDS)
web/                     Svelte 5 + Vite, compilé puis embarqué (go:embed)
client/packages/romsync_core/   Dart pur : toute la logique du client
client/app/              Flutter : interface seulement (Linux, macOS, Windows)
3ds/core/                C99 portable (sans libctru) : toute la logique du
                         homebrew 3DS, testée sous Linux (3ds/tests)
3ds/app/                 couche 3DS (libctru) : écrans, clavier, réseau, lancement
profiles/*.json          profils de conversion partagés (copiés dans l'appli
                         par client/tool/sync_profiles.sh)
api/openapi.yaml         spécification de l'API
keys/release-ed25519.pub clé publique de signature des releases (docs/releasing.md)
testdata/ed25519/        vecteurs Ed25519 (RFC 8032, openssl, verdicts.json) partagés
                         par les tests Dart et C
client/packages/romsync_updater/   remplacement d'une installation avec retour
                         arrière (romsync-updater.exe sous Windows)
deploy/                  Dockerfile (compilation croisée amd64/arm64), compose
.github/workflows/       ci.yml, build-client.yml et build-3ds.yml (réutilisables),
                         release.yml
```

## Environnement local

- Go 1.27 dans `~/.local/go` (le `go` système est gccgo 1.18, inutilisable) et
  Flutter 3.47.9 dans `~/.local/flutter` :
  `export PATH=$HOME/.local/flutter/bin:$HOME/.local/go/bin:$PATH`.
- Pas de Docker : utiliser `podman build -f deploy/Dockerfile .`.
- `grep` est un alias de ripgrep : utiliser `rtk proxy grep` pour le grep GNU,
  et `rtk proxy curl` quand on redirige du JSON.
- Pas d'affichage virtuel : pour voir un écran Flutter, rendre une image via un
  test golden temporaire (polices dans
  `~/.local/flutter/bin/cache/artifacts/material_fonts`), puis le supprimer.
- Ne jamais lancer `pkill -f <chemin>` dans une commande qui contient ce chemin
  (cela tue le shell lui-même).

## Commandes

```sh
make test          # Go (-race), svelte-check, tests web, tests du client
make lint          # golangci-lint (server/.golangci.yml), doit rester à 0
make build         # server/bin/romsync avec le site embarqué
make client-test   # flutter analyze + tests romsync_core + tests de l'appli
make client-e2e    # bout en bout du client contre le vrai serveur Go
make client-build  # build Linux du client (copie les profils avant)
make 3ds-test      # tests du cœur C du homebrew 3DS (gcc, libcurl-devel)
make 3ds-e2e       # bout en bout du cœur C contre le vrai serveur Go
```

Build 3DS (devkitPro n'est pas installé) :
`podman run --rm -v "$PWD":/src:Z -w /src/3ds docker.io/devkitpro/devkitarm make`.
`make cia` demande makerom et bannertool : seulement en CI (ne pas exécuter
en local des binaires téléchargés).

Lint OpenAPI : `npx --yes @redocly/cli@1 lint api/openapi.yaml`.

## Règles à respecter

- **Le client ne coupe jamais une save** : il retire seulement l'en-tête ou le
  pied du profil. Les règles de taille sont côté serveur (section « Taille
  réelle » de la spec).
- L'état local est tenu **par fichier de save**, pas par jeu. Tout envoi passe
  par la file persistée (UUID `X-Upload-Id` généré une fois).
- Les ROMs qui partagent un identifiant ne sont pas synchronisées tant que
  l'utilisateur n'a pas choisi « partager » ou « séparer ».
- En arrière-plan (barre système), le client n'envoie que ; il ne télécharge
  jamais.
- Le jeton d'appareil n'est jamais écrit en clair sans choix explicite de
  l'utilisateur (trousseau, Keychain « login », Gestionnaire d'identifiants
  Windows sous « RomSync »).
- Modifier le schéma par une nouvelle migration, jamais en éditant une
  migration publiée. Modifier un profil : relancer
  `client/tool/sync_profiles.sh`.

## Pièges connus

- Tests de l'appli : passer à `AppController` un `environment` avec un `HOME`
  temporaire, jamais le vrai (un test pourrait déplacer de vraies saves de
  `~/.config/desmume`).
- Les tests qui simulent Linux avec des chemins POSIX sont marqués
  `!windows` ; le comportement propre à Windows est dans
  `windows_emulators_test.dart`. Les chemins se construisent avec le contexte
  de l'OS ciblé (`p.Context`), pas celui de l'hôte.
- Tests de surveillance de fichiers : attendre une condition (`eventually`),
  pas un délai fixe (FSEvents regroupe les événements sur macOS).
- `flutter create --platforms=…` sur l'appli existante recrée
  `test/widget_test.dart` et modifie `analysis_options.yaml` : annuler ces
  changements.
- `tray_manager` 0.8 et `window_manager` 0.6 reposent sur `nativeapi` ; l'appli
  l'utilise directement (pas l'API `legacy.dart`). Sous Linux, aucune
  dépendance AppIndicator/libnotify, mais les en-têtes GTK 3, X11 et Xi sont
  nécessaires même pour `flutter test`.
- Homebrew 3DS : le cœur (`3ds/core`) suit `romsync_core` méthode par
  méthode ; toute décision de synchro modifiée d'un côté l'est de l'autre,
  avec le même cas de test (`sync_test.dart` / `3ds/tests/test_sync.c`).
- 3DS : la console de libctru affiche en CP437 (passer par `ui_print`) ; la
  carte SD refuse un `rename` vers un fichier existant ; la date des saves
  n'est pas fiable (nds-bootstrap ne met pas à jour l'entrée FAT).
- Divergence (deux appareils ont joué sans se synchroniser) : jamais d'envoi
  ni d'écrasement sans le choix de l'utilisateur (`X-Activate`). La
  comparaison passe par les règles de taille du serveur : `size_rule.dart` et
  `3ds/core/size_rule.c` doivent rester identiques à
  `server/internal/syncrule/size.go`.
- Les dates envoyées sont à la seconde et le serveur garde la version active
  en cas d'égalité : dans les tests de bout en bout, attendre une seconde
  entre deux saves qui doivent se succéder.
- Mises à jour : la clé publique existe en trois copies (`keys/`,
  `release.dart`, `core/update.h`), vérifiées par des tests. Un build sans
  version (`dev`, local ou CI) ne se met jamais à jour. Les serveurs des tests
  de bout en bout tournent avec `ROMSYNC_UPDATES=off` (pas d'accès à GitHub).
- Compatibilité : toute fonction nouvelle dont dépend un client augmente
  `APILevel` (server/internal/api/updates.go) et le niveau demandé par les
  clients (`requiredServerApiLevel`, `RS_REQUIRED_API_LEVEL`).
- Les fichiers de test réels (pieds de `.dsv`) ne contiennent que des tailles
  et le cookie : ne jamais versionner de save de jeu commercial.

## En attente

- Profil flashcard : `to_verify` jusqu'au test sur DSTT.
- Profil `twilight` (3DS) : `to_verify` jusqu'aux tests manuels de
  l'utilisateur sur sa 2DS (`docs/tests-manuels-3ds.md`) ; la couche 3DS et
  le `.cia` n'ont encore jamais tourné sur une console.
- Phases suivantes : 5 (Android, en attente d'un testeur :
  l'utilisateur n'a pas de téléphone Android, recherches dans
  `docs/research/android.md`), 6 (iOS, à étudier, rien n'est codé).
