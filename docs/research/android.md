# Client Android — recherches (phase en attente d'un testeur)

Recherches faites en novembre 2026 avant le début de la phase Android, mise en
pause faute de téléphone Android pour tester. Ce document sert à la reprendre
ou à guider un contributeur. Rien n'est codé ; `docs/SPEC.md` fait toujours foi.

Légende : **vérifié** = lu dans les sources ou la configuration d'un projet
tiers ; **incertain** = à confirmer sur un vrai téléphone.

## melonDS Android (`me.magnum.melonds`)

Source : <https://github.com/rafaelvcaetano/melonDS-android> (lu sur la branche
principale, novembre 2026).

- **Vérifié** — nom de la save : nom de fichier de la ROM avec l'extension
  remplacée par `.sav` (`romFileName.replaceAfterLast('.', "sav", …)`,
  `app/src/main/java/me/magnum/melonds/impl/emulator/SramProvider.kt`). Une ROM
  `jeu.zip` donne donc `jeu.sav`. Format brut (profil `melonds`).
- **Vérifié** — dossier : à côté de la ROM par défaut (préférence `use_rom_dir`,
  vraie par défaut), sinon le dossier SAF choisi dans ses réglages (`sram_dir`)
  (`impl/SharedPreferencesSettingsRepository.kt`, `getSaveFileDirectory`). Ces
  réglages sont dans ses préférences privées : RomSync ne peut pas les lire,
  l'utilisateur doit indiquer le même dossier.
- **Vérifié** — piège : une ROM lancée par intent est cherchée dans la
  bibliothèque de melonDS (par URI, par chemin absolu, puis par nom et taille,
  `impl/FileSystemRomsRepository.kt`, `getRomAtUri`). Si elle n'y est pas, son
  dossier parent est inconnu et la save part dans
  `Android/data/me.magnum.melonds/files/saves`, privé et inaccessible par SAF.
  Le dossier de ROMs doit donc aussi être ajouté dans la bibliothèque de
  melonDS.
- **Vérifié** — lancement : `EmulatorActivity` (`launchMode="singleTask"`,
  exportée) répond à l'action `me.magnum.melonds.LAUNCH_ROM` (`${applicationId}.LAUNCH_ROM`
  dans `AndroidManifest.xml`) ; la ROM est passée par l'extra `uri` (chaîne ou
  `Uri`), par `intent.data`, ou par un chemin (`KEY_PATH`)
  (`ui/emulator/model/LaunchArgs.kt`). Variantes : `me.magnum.melonds.nightly`
  (action `me.magnum.melonds.nightly.LAUNCH_ROM`), `me.magnum.melondualds`.
- **Vérifié** — archives : `.zip` et `.7z` pris en charge
  (`impl/romprocessors/Api24RomFileProcessorFactory.kt`).
- **Incertain** — moment où la save est écrite pendant la partie (melonDS sur
  PC écrit peu après chaque sauvegarde en jeu ; à confirmer sur Android).

## DraStic (`com.dsemu.drastic`)

Source fermée : rien n'a pu être lu dans le code.

- **Vérifié (configuration d'ES-DE)** — lancement : activité
  `com.dsemu.drastic/.DraSticActivity`, URI SAF de la ROM dans `data`, drapeaux
  `ACTIVITY_CLEAR_TASK` et `ACTIVITY_CLEAR_TOP`.
- **Incertain** — format des `.dsv`. Les guides se contredisent : simple brut
  renommé, ou brut suivi du pied DeSmuME de 122 octets. Pour trancher : la
  taille d'un vrai `.dsv` DraStic et ses 122 derniers octets
  (`tail -c 122 jeu.dsv | xxd`), sans versionner la save. En lecture, le profil
  peut accepter les deux (retirer le pied s'il porte le cookie
  `|-DESMUME SAVE-|`) ; en écriture, il faut reproduire ce que DraStic produit.
- **Incertain** — dossier : sans réglage, `Android/data/com.dsemu.drastic/…`
  (privé, inaccessible par SAF depuis Android 11). Avec « System Directory » →
  « Scoped Storage Folder » sur un dossier partagé : `<dossier>/backup/`.
- **Incertain** — nom exact du fichier (a priori nom de la ROM sans extension +
  `.dsv`), archives prises en charge, moment de l'écriture de la save.

## RetroArch Android + melonDS DS

Source : <https://github.com/libretro/RetroArch> (`frontend/drivers/platform_unix.c`,
`config.def.h`, novembre 2026). Le profil `retroarch-melondsds` (`.srm` brut)
est confirmé sur Windows.

- **Vérifié** — paquets : `com.retroarch.aarch64` (site retroarch.com, 64 bits),
  `com.retroarch.ra32`, `com.retroarch` (Play Store). Activité :
  `com.retroarch.browser.retroactivity.RetroActivityFuture`.
- **Vérifié** — extras lus par `getStringExtra` : `ROM` (chemin de fichier, pas
  une URI), `LIBRETRO` (cœur, ex.
  `/data/data/com.retroarch.aarch64/cores/melondsds_libretro_android.so`),
  `CONFIGFILE`, ainsi que `IME`, `DATADIR`, `SDCARD`, `EXTERNAL`, `APK`, `USED`,
  `AUDIO_RATE`, `AUDIO_FRAMES`, `VULKAN_DRIVER`.
- **Vérifié** — sans `CONFIGFILE`, `retroarch.cfg` est cherché dans
  `getExternalFilesDir()` (`Android/data/<paquet>/files/retroarch.cfg`), puis
  dans `getFilesDir()` (`android_env_derive_config_path`). Les deux sont
  inaccessibles par SAF depuis Android 11 : **impossible de lire
  `retroarch.cfg` comme sur PC.**
- **Vérifié** — dossier des saves par défaut : `/storage/emulated/0/RetroArch/saves`
  si le stockage partagé est inscriptible (RetroArch a l'accès à tous les
  fichiers), sinon `Android/data/<paquet>/files/saves` (privé ; cas de la
  version Play Store), sinon le dossier interne de l'appli.
- **Vérifié** — `sort_savefiles_enable` vaut vrai par défaut,
  `sort_savefiles_by_content_enable` et `savefiles_in_content_dir` faux : la
  save est par défaut dans `saves/melonDS DS/<rom>.srm`.
- Proposition : l'utilisateur choisit le dossier des saves de RetroArch par le
  sélecteur système et indique ses deux réglages de tri (valeurs par défaut de
  RetroArch proposées).
- **Incertain** — conversion de l'URI SAF de la ROM en chemin pour l'extra
  `ROM` : `primary:<chemin>` → `/storage/emulated/0/<chemin>`,
  `<uuid>:<chemin>` → `/storage/<uuid>/<chemin>` (carte SD). Archives :
  « indisponible », comme sur PC.

Référence croisée pour les trois émulateurs : configuration Android d'ES-DE,
`resources/systems/android/es_systems.xml` (système `nds`) et
`es_find_rules.xml`.

## Architecture envisagée

- **Stockage** : `romsync_core` utilise `dart:io` partout. Ajouter une interface
  de stockage pour les ROMs et les saves (lister, lecture stable, taille et
  date, écriture, `.backup`), avec une implémentation `dart:io` (PC, sans
  changement de comportement) et une implémentation SAF dans l'appli via un
  canal Kotlin (`DocumentsContract`, permissions persistantes). L'état, la file
  d'envoi et `failed` restent dans le dossier privé de l'appli, en `dart:io`.
- **Archives** : `.zip` lisible par accès aléatoire via le canal ; `.7z`
  illisible (pas de programme `7z` sur Android, pas de décodeur Dart pur fiable)
  → « identification impossible sur Android », écart à faire valider.
- **Lancement** : `LaunchPlan` devient « processus » (PC) ou « intent »
  (Android). Les URI passées à un émulateur portent
  `FLAG_GRANT_READ_URI_PERMISSION` (et écriture si besoin).
- **Pendant la partie** : service de premier plan Kotlin minimal (type
  `dataSync`, notification « Synchronisation active »), scrutation du fichier
  toutes les 5 s dans le moteur Dart (gardé en cache par l'`Application` pour
  survivre à l'activité), dernier passage au retour dans l'appli.
- **Hors partie** : WorkManager (période minimale 15 min) qui notifie les saves
  plus récentes, sans jamais écrire de fichier. Question ouverte : doit-il aussi
  envoyer les saves modifiées, comme la barre système sur PC ?
- **Jeton** : `flutter_secure_storage` (chiffrement adossé au Keystore Android).
- **Réseau** : Android bloque `http://` par défaut ; l'appairage utilise
  `http://nas:8080`. Il faut une configuration de sécurité réseau qui l'autorise
  (avec avertissement hors réseau privé et Tailscale `100.64.0.0/10`), ou HTTPS.
- **Batterie** : `PowerManager.isIgnoringBatteryOptimizations`, puis guide vers
  le réglage (et les surcouches des constructeurs, voir dontkillmyapp.com).

## Contraintes d'Android à respecter

- Android 12+ : un service de premier plan ne démarre pas depuis l'arrière-plan
  (ici il démarre quand l'appli est au premier plan, avant l'intent).
- Android 13+ : permission `POST_NOTIFICATIONS` demandée à l'exécution.
- Android 14 : type de service obligatoire (`foregroundServiceType="dataSync"`
  et permission `FOREGROUND_SERVICE_DATA_SYNC`) ; la notification peut être
  balayée sans arrêter le service.
- Android 15 : `dataSync` limité à 6 h par 24 h (`Service.onTimeout()` : faire
  un dernier passage et s'arrêter en quelques secondes) ; pas de démarrage
  `dataSync` depuis `BOOT_COMPLETED`.

## Tests

- `romsync_core` : profils (aller-retour), noms de saves, sous-dossiers
  RetroArch, URI → chemin, dossiers privés, archives par émulateur.
- CI : compiler l'APK arm64. Un émulateur Android en CI est faisable (KVM sur
  les runners Ubuntu) mais peu utile : le sélecteur SAF est une interface
  système, DraStic et RetroArch configuré ne s'installent pas, Doze et les
  optimisations des constructeurs ne sont pas reproduits. Prévoir plutôt une
  liste de tests manuels avec le résultat attendu.

## Publication

- APK signé dans la GitHub Release sur un tag `v*`. La clé ne va jamais dans
  le dépôt :
  ```sh
  keytool -genkeypair -v -keystore romsync-release.jks -alias romsync \
    -keyalg RSA -keysize 4096 -validity 10000
  base64 -w0 romsync-release.jks > romsync-release.jks.b64
  ```
  Secrets GitHub : `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`,
  `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`. La CI recrée le fichier dans le
  runner ; hors tag, signature de debug. Perdre la clé empêche d'installer les
  mises à jour par-dessus l'ancienne version.

## Questions à trancher à la reprise

1. Modèle et version d'Android du testeur.
2. Identifiant d'appli (proposition : `io.github.dadoux01.romsync`, définitif
   après la première installation).
3. `http://` autorisé partout avec avertissement, ou HTTPS obligatoire.
4. WorkManager : notifier seulement, ou aussi envoyer.
5. `.7z` : « identification impossible sur Android ».
6. Format réel des `.dsv` de DraStic.

## Sources

- melonDS Android : <https://github.com/rafaelvcaetano/melonDS-android>
- RetroArch : <https://github.com/libretro/RetroArch> (`frontend/drivers/platform_unix.c`, `config.def.h`)
- ES-DE, configuration Android :
  <https://gitlab.com/es-de/emulationstation-de/-/raw/master/resources/systems/android/es_systems.xml>,
  <https://gitlab.com/es-de/emulationstation-de/-/raw/master/resources/systems/android/es_find_rules.xml>
- `.dsv` de DraStic (sources contradictoires) : <https://www.ghacks.net/?p=160953>,
  <https://projectpokemon.org/home/tutorials/save-editing/managing-nds-saves/using-emulators-r71/>
- Dossier DraStic sur Android récent (guide tiers) :
  <https://joeysretrohandhelds.com/guides/where-to-find-save-files-for-every-emulator-and-custom-firmware/>
- Services de premier plan : <https://developer.android.com/develop/background-work/services/fgs/service-types>,
  <https://developer.android.com/about/versions/15/behavior-changes-15#datasync-timeout>
