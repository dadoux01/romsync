# RomSync client

Desktop client of RomSync for **Linux** (x86-64, ARM64), **macOS** (Apple
Silicon, Intel) and **Windows** (x64): it finds your DS ROMs, launches them in
your emulator and syncs their saves with your RomSync server around each game.
Android comes in the next phase. Installation from the release archives is
described in the [main README](../README.md#client-installation).

## What it does

- **Pairing**: server address, the 8-character code shown on the website
  (*Appareils → Ajouter un appareil*) and a device name. The device token is
  stored in the system's secret store: the keyring on Linux (Secret Service:
  GNOME Keyring, KWallet, KeePassXC…), the login keychain on macOS, the
  Credential Manager on Windows (generic credential `RomSync`). On Linux
  without a keyring — common on Hyprland or other minimal sessions — pairing
  stops and offers to store the token in a 0600 file instead, with a warning.
- **Library**: one or more ROM folders, scanned recursively for `.nds` files,
  including inside `.zip` (read directly) and `.7z` archives (read with the
  `7z`, `7zz` or `7za` program: install `p7zip`/`7zip` on Linux,
  `brew install sevenzip` on macOS, 7-Zip on Windows). Games are identified
  by the code in the ROM header, or `h:<sha1>` for homebrew.
- **ROMs sharing a game code** (patched ROMs, translations, hacks): the list
  flags them and asks, once per ROM, whether it *shares* the save of the game
  or is *separated* under a forced `x:` identifier you name. Until you answer,
  these ROMs are not synced.
- **Save states in the list**: up to date, to upload, to download, offline,
  choice required, unavailable, and "conflit résolu automatiquement".
- **Playing**: before launching, the client sends queued uploads, uploads a
  save changed outside a sync, downloads a newer server save (the replaced
  local save is copied to a `.backup` folder next to it; 10 copies kept per
  save by default). During the game, each in-game save is uploaded after 5 s
  without writes; a last upload happens when the emulator exits. A save is
  only read when complete and stable, and files kept open by an emulator
  (Windows) are retried: a half-written save is never sent.
- **Offline**: the game still launches, with a warning. Uploads wait in a
  queue on disk and leave as soon as the server answers; each keeps the same
  upload id across retries and restarts, so nothing is duplicated.
- **System tray**: closing the window keeps RomSync in the tray (configurable).
  Saves of games launched without RomSync are then uploaded after 5 s
  without writes; nothing is downloaded in the background (the emulator may
  have the save open), but a notification names the game and the device a
  newer server save comes from. On Linux the icon uses StatusNotifierItem:
  KDE shows it, GNOME needs the AppIndicator extension, Hyprland a bar with a
  tray (waybar).
- **History**: read-only list of a game's versions, with a link to the
  website to restore one.

The client never cuts a save: it only removes the emulator's header or footer
and sends the raw save; size normalisation is the server's job.

## Emulators

Choose the default emulator in *Réglages → Émulateurs*, and another one per
game from the emulator menu of the game in the list (all the ROMs of a game
follow that choice). A save moves from one emulator to another: switching a
game to DeSmuME writes its `.dsv` from the server save before the next game.
If the new emulator already has a save for the game that RomSync never synced
(an old game), RomSync shows it and offers to set it aside in `.backup`.

ROMs inside archives can only be launched with melonDS in this version; with
DeSmuME or RetroArch they are shown as unavailable.

| Emulator | Save file | Install modes |
| --- | --- | --- |
| melonDS | `<rom>.sav`, raw | executable / `.app`, Flatpak `net.kuribo64.melonDS` |
| DeSmuME | `<rom>.dsv`, raw + 122-byte footer | executable / `.app`, Flatpak `org.desmume.DeSmuME` |
| RetroArch + melonDS DS | `<rom>.srm`, raw (*format to verify*) | executable / `.app`, Flatpak `org.libretro.RetroArch` |

### melonDS

- **Save folder**: `SaveFilePath` in `melonDS.toml` (or the older
  `melonDS.ini`), looked up like melonDS does: a `portable` folder next to
  the executable (next to the `.app` on macOS), the executable's folder for
  Windows portable builds, then `~/.config/melonDS` (Linux),
  `~/Library/Preferences/melonDS` (macOS) or `%LOCALAPPDATA%\melonDS`
  (Windows); `~/.var/app/net.kuribo64.melonDS/config/melonDS` for the
  Flatpak. Empty means next to the ROM, melonDS's default.
- **Flatpak**: it can only reach your home folder by default; for ROMs
  elsewhere (another disk, `/mnt`, `/run/media`…), the client shows the
  command to run, for example
  `flatpak override --user --filesystem=/mnt/games/nds net.kuribo64.melonDS`.

### DeSmuME

- **Save folder** (Battery), computed like DeSmuME does: always
  `~/.config/desmume` on Linux (`~/.var/app/org.desmume.DeSmuME/config/desmume`
  for the Flatpak); `[PathSettings] Battery` of `desmume.ini` next to the
  executable on Windows (`.\Battery` by default); the single
  `~/Library/Application Support/DeSmuME/<version>/Battery` folder on macOS,
  else you choose it in the settings.
- **Flatpak**: `org.desmume.DeSmuME` has **no** file access by default; the
  client shows a read-only override per ROM folder, e.g.
  `flatpak override --user --filesystem=/home/me/Jeux:ro org.desmume.DeSmuME`.
- **macOS**: DeSmuME's Cocoa app is started with `open -W -n -a`, which waits
  for that instance to quit.

### RetroArch with melonDS DS

- Install the core from RetroArch: *Main Menu → Load Core → Download a Core →
  Nintendo - DS (melonDS DS)*. RomSync finds it in `libretro_directory` and
  launches `retroarch -L <core> <rom>`.
- **Save folder**: read from `retroarch.cfg` (and the `melonDS DS` core,
  content-folder and game overrides): `savefile_directory`, the ROM's folder
  when empty or with `savefiles_in_content_dir`, plus the ROM folder's name
  with `sort_savefiles_by_content_enable`, plus `melonDS DS` with
  `sort_savefiles_enable`.
- The `.srm` format is the raw SRAM in melonDS DS's sources; the profile stays
  *to verify* until a real round trip with RetroArch has been checked.

## Files

| | Linux | macOS | Windows |
| --- | --- | --- | --- |
| Settings | `~/.config/romsync/config.json` | `~/Library/Application Support/RomSync/config.json` | `%APPDATA%\RomSync\config.json` |
| Sync state, queue | `~/.local/share/romsync/` | `~/Library/Application Support/RomSync/data/` | `%LOCALAPPDATA%\RomSync\` |
| Token (file option) | `~/.config/romsync/token` (0600) | — | — |

`XDG_CONFIG_HOME` and `XDG_DATA_HOME` are honoured on Linux. Replaced local
saves are kept in a `.backup` folder next to each save.

## Building

Flutter 3.47 or later, plus Go to run the end-to-end tests.

- **Linux (Fedora)**:
  `sudo dnf install clang cmake ninja-build pkgconf-pkg-config gtk3-devel libsecret-devel p7zip`.
  On x86-64 download Flutter's Linux archive; on ARM64 (Fedora Asahi) Flutter
  only publishes x64 archives, so install it with git — the tool then
  downloads the ARM64 engine itself:
  `git clone --depth 1 --branch 3.47.9 https://github.com/flutter/flutter.git ~/.local/flutter`.
  The ARM64 build must run on an ARM64 machine: Flutter cannot cross-compile
  Linux desktop apps.
- **macOS**: Xcode and its command-line tools; the build is universal (Apple
  Silicon and Intel). The app runs without the App Sandbox (it launches
  emulators and reads ROM folders anywhere).
- **Windows**: Visual Studio with the *Desktop development with C++* workload.

From the repository root:

```sh
make client-test    # analyze + unit tests (romsync_core and app)
make client-e2e     # end-to-end tests against the real Go server (needs Go)
make client-build   # Linux: client/app/build/linux/<arch>/release/bundle/romsync
```

On macOS and Windows, run `flutter build macos` or `flutter build windows` in
`client/app`. `make client-build` first copies `profiles/*.json` into the app's
assets (`client/tool/sync_profiles.sh`); a test fails if the copies are stale.
Releases are built by `.github/workflows/build-client.yml`.

## Layout

```
client/
├── packages/romsync_core/   pure Dart: API client, NDS headers, archives, profiles,
│                            local state, upload queue, sync engine, emulators,
│                            background watcher
├── app/                     Flutter interface (Linux, macOS, Windows), tray,
│                            platform secret stores
└── tool/sync_profiles.sh    copies profiles/ into the app's assets
```

`romsync_core` has no Flutter dependency and is tested with `dart test`; the
end-to-end tests (`dart test -t e2e`) build and start the real server.
