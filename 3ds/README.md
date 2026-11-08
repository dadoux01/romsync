# RomSync for the 3DS

A homebrew app that syncs the saves of the DS games you play on a 3DS with
TWiLight Menu++ and nds-bootstrap. It talks to the same RomSync server as
the desktop client, with the same rules (docs/SPEC.md, "Protocole de
synchronisation"), so a save moves between the 3DS and melonDS, DeSmuME or
RetroArch on a PC.

- **Sync at startup**: RomSync first sends the saves you changed since the
  last start, then downloads the newer saves from the server (the replaced
  file is kept in a `.backup` folder next to the save, 10 copies at most).
- **Optional launch**: with YANBF installed, RomSync can start a game itself,
  after syncing it. Without it, start your games from TWiLight Menu++.
- **Open RomSync right after playing.** The 3DS cannot run RomSync while a
  DS game runs, so your save leaves the console the next time RomSync
  starts. Opening it right after playing sends the save at once, with the
  right date (see [Dates](#dates)).

## Requirements

- A 3DS or 2DS with Luma3DS (custom firmware).
- TWiLight Menu++ with nds-bootstrap, the usual way to play DS games from
  the SD card. RomSync reads its settings to find the saves.
- The RomSync server reachable **on the local network**: Tailscale does not
  exist on the 3DS. Use the server's LAN address, e.g.
  `http://192.168.1.10:8085`.
- Optional, to launch games from RomSync: YANBF's `bootstrap.cia` and the NTR
  forwarder pack (see [Launching a game](#launching-a-game)).

## Installation

Download from the [Releases](https://github.com/dadoux01/romsync/releases)
page:

- `romsync-<version>-3ds.cia`: copy it to the SD card and install it with
  FBI (or another CIA installer). RomSync then appears on the HOME Menu.
  **Use the CIA** if you want to launch games from RomSync.
- `romsync-<version>-3ds.3dsx`: copy it to `sd:/3ds/` and start it from the
  Homebrew Launcher. Syncing works; launching games may not.

## First start

1. **Pairing.** On the RomSync website, open *Appareils → Ajouter un
   appareil* to get a code. On the 3DS, type the server address, the code
   and a name for the console with the system keyboard. The device token is
   stored **in clear** in `sd:/3ds/romsync/token.txt`, as the specification
   allows: if the SD card is lost, revoke the device on the website.
2. **ROM folders.** If `sd:/roms/nds/` exists, RomSync suggests it.
   Otherwise, or to add other folders, a small browser of the SD card opens:
   *Up/Down* to move, *A* to open a folder, *B* to go back, *X* to choose the
   current folder. For each folder, choose whether its sub-folders are
   scanned too. Folders can be changed later in the settings (*SELECT*).
3. RomSync scans the folders (it tells you when a folder holds no `.nds`),
   then syncs every game.

## Using the app

Top screen: the games and the state of their save (*à jour*, *à envoyer*,
*hors ligne*, *pas de save*, *choix requis*, *choix à faire*, *erreur*; `*`
marks a divergence recorded on the server). Bottom screen: details of
the selected game and the keys.

| Key | Action |
| --- | --- |
| Up/Down, Left/Right | Move, page by page |
| A | Sync the selected game |
| R | Sync all games |
| X | Launch the game (needs YANBF) |
| Y | Share or separate the save, when several ROMs share an identifier |
| SELECT | Settings: ROM folders, number of `.backup` copies, pairing |
| START | Quit |

**ROMs sharing an identifier** (a translation or a hack of the same game):
RomSync does not sync them until you choose, ROM by ROM, to share the save
or to separate it under a new name, so that a variant never overwrites
another one's save.

**Save slots.** TWiLight Menu++ can keep up to ten saves per game (`.sav`,
`.sav1` to `.sav9`, per-game setting). RomSync syncs only the active slot,
shown in the details of the game. When the slot changes and the new slot
already holds a file that RomSync never synced for this game, RomSync asks
before sending it: it is probably an old save. You can set it aside in
`.backup` (the server's save is then downloaded into the slot) or send it:
it then becomes the active save.

**Two devices played without syncing** (for example, you played on the PC,
then on the console without opening RomSync in between): RomSync sends
nothing and overwrites nothing, and asks. *A* sends the console's save (it
becomes the active one), *Y* takes the server's (the console's save stays in
the history on the website and in `.backup`), *B* postpones: the question
comes back at the next start, and a game launched with *X* does not start.
The comparison ignores the zeros TWiLight Menu++ adds at the end of the file
(`core/size_rule.c` applies the server's size rules).

**Offline.** Without Wi-Fi or server, RomSync keeps the changed saves in a
queue (`sd:/3ds/romsync/queue/`) and sends them at the next start where the
server answers. A retry never creates a duplicate version.

## Dates

Without a divergence, the server keeps the most recent save active
(`saved_at`). On the 3DS two things make dates unreliable:

1. **The file date does not change while playing.** nds-bootstrap writes the
   save sectors directly on the SD card (`retail/common/source/my_fat.c`,
   `fileWrite`), without updating the file's directory entry. RomSync
   therefore detects a change by its content (SHA-256), and dates it **when
   RomSync first sees it**. Hence the advice to open RomSync right after
   playing. A save seen late cannot win silently against a newer save of
   another device, though: that is a divergence, and RomSync asks.
2. **The console clock is often wrong**, and the 3DS has no time zone. Each
   answer of the server carries a `Date` header: RomSync measures the gap
   between that date and the console clock, and adds it to the dates it
   sends. A console that is 3 hours late still dates its saves correctly.
   The last measured gap is kept in `state.json` for uploads made offline.

## TWiLight Menu++

Verified in the sources of TWiLight Menu++ (`title/arm9/source/main.cpp`,
`universal/source/common/twlmenusettings.cpp`, `pergamesettings.cpp`):

- Save folder: `SAVE_LOCATION` in `[SRLOADER]` of
  `sd:/_nds/TWiLightMenu/settings.ini`: `0` (default) the `saves` folder of
  the ROM's folder, `1` next to the ROM, `2` `sd:/_nds/TWiLightMenu/saves/`.
- Save name: the ROM's file name with its extension replaced by `.sav`, or
  `.sav1` to `.sav9` for the slot `SAVE_NUMBER` of
  `sd:/_nds/TWiLightMenu/gamesettings/<ROM file>.ini` (ignored with
  `SAVE_LOCATION=1`).
- Format: raw (profile `twilight`). At launch, TWiLight Menu++ creates the
  file or **grows** it to the size of its own ROM list (512 KiB for unknown
  games), filling with zeros; it never shrinks it. RomSync writes the save
  at its real size and lets TWiLight Menu++ pad it; the server then cuts the
  padding, so the padded file creates no new version.
- DSiWare saves (`.pub`, `.prv`) are not synced.

## Launching a game

A 3DS-mode app cannot start a `.nds` file: the game must run in DSi mode.
RomSync uses the method of [YANBF](https://github.com/YANBForwarder/YANBF),
whose forwarders do exactly this:

1. RomSync syncs the game (offline: it warns and launches anyway);
2. it writes the ROM path, as DS-mode programs see it
   (`sd:/roms/nds/Game.nds`), in `sd:/_nds/ntr-forwarder/path.txt`;
3. it asks the system to jump to YANBF's `bootstrap.cia` (DSi-mode title
   `0004800546574452`), which starts the NTR forwarder
   (`sd:/_nds/ntr-forwarder/sdcard.nds`), which runs nds-bootstrap.

To enable it, install:

1. `bootstrap.cia` from the [YANBF releases](https://github.com/YANBForwarder/YANBF/releases), with FBI;
2. the *DS Game Forwarder Pack* from the
   [NTR_Forwarder releases](https://github.com/RocketRobz/NTR_Forwarder/releases):
   copy the content of *for SD card root* to the root of the SD card.

The forwarder has **its own save settings**: `SAVE_LOCATION` in
`[NTR-FORWARDER]` of `sd:/_nds/ntr_forwarder.ini` and per-game slots in
`sd:/_nds/ntr-forwarder/gamesettings/`. If they would make the game use
another save file than TWiLight Menu++, RomSync blocks the launch and tells
you what to change. When the game ends, the console goes back to the HOME
Menu; open RomSync to send the save.

## Files on the SD card

| Path | Content |
| --- | --- |
| `sd:/3ds/romsync/config.json` | Server address, device name, ROM folders, your choices |
| `sd:/3ds/romsync/token.txt` | Device token (in clear) |
| `sd:/3ds/romsync/state.json` | Sync state of each save file, clock gap |
| `sd:/3ds/romsync/queue/` | Uploads waiting for the server; `failed/` for refused ones |
| `sd:/3ds/romsync/profiles/` | Optional: conversion profiles replacing the built-in ones |
| `<save folder>/.backup/` | Copies of the saves replaced by a download |

## Architecture

The code is split in two layers, so that almost everything can be built and
tested on Linux, where debugging is easy:

```
3ds/
  core/        portable C99: no libctru, compiled on Linux and on the 3DS
  app/         3DS layer: libctru (screens, keyboard, network, launch)
  vendor/cjson cJSON 1.7.18 (MIT), JSON parser
  tests/       unit tests and end-to-end test of core/, on Linux
  meta/        icon, banner and CIA settings
  Makefile     3DS build (devkitPro)
```

### core/: the logic, without the console

| File | Role | Same as in romsync_core (Dart) |
| --- | --- | --- |
| `rs.c` | byte buffers, errors, strings, files | `state/json_file.dart`, `file_access.dart` |
| `sha.c` | SHA-1 and SHA-256 | package `crypto` |
| `nds.c` | ROM header, game identifiers | `rom/nds_header.dart`, `rom/game_id.dart` |
| `profile.c` | conversion profiles (`profiles/*.json`) | `profiles/profile.dart` |
| `clock.c` | ISO and HTTP dates, clock gap | (3DS only) |
| `state.c`, `queue.c` | state per save file, upload queue | `state/save_state.dart`, `state/upload_queue.dart` |
| `api.c`, `http.h`, `http_curl.c` | REST API client, HTTP with libcurl | `api/api_client.dart` |
| `sync.c` | sync decisions, statuses, `.backup` | `sync/engine.dart`, `sync/status.dart`, `sync/backups.dart` |
| `twilight.c` | TWiLight Menu++ and forwarder settings | (3DS only) |
| `config.c`, `library.c` | app settings, ROM scan, library | `state/config.dart`, `rom/scanner.dart`, `sync/library.dart` |

`sync.c` follows `engine.dart` method by method, and `tests/test_sync.c`
repeats the cases of `sync_test.dart`, so both clients take the same
decisions. The differences are 3DS rules: the date of a save
([Dates](#dates)) and the save slot change.

### Choices, and why

- **Two layers.** The 3DS layer is small (screens, keyboard, network start,
  launch): what can go wrong in the sync logic is caught by tests on a PC.
- **The system is behind two seams**, so that tests can replace it:
  - `platform.h` (random bytes, clock), implemented by `app/platform_3ds.c`
    on the 3DS and `tests/platform_linux.c` on Linux, chosen at link time;
  - the HTTP transport, a function pointer in `rs_api`: libcurl in the app
    and the end-to-end test, an in-memory fake server
    (`tests/fake_server.c`) in the unit tests.
- **libcurl on both sides.** devkitPro ships it for the 3DS (portlib
  `3ds-curl`, built with mbedtls, so HTTPS is possible later). The same
  `http_curl.c` runs in the end-to-end test against the real Go server and
  on the console. libctru's `httpc` service would have needed a second,
  untested implementation.
- **cJSON** is one readable file, widely used, MIT-licensed (compatible with
  the AGPL-3.0). Profiles are JSON precisely so that C can read them simply.
- **SHA-1 and SHA-256 are written here** (about 200 lines, commented, checked
  against the official test vectors) rather than taken from mbedtls: one
  dependency less on Linux, and they are a good read.
- **Errors**: every function that can fail returns an `rs_status` and fills
  an optional `rs_error` with a French message for the user. No global
  error state.
- **Memory**: growable buffers (`rs_buf`) and small `realloc`'ed arrays;
  every structure has its `_free`/`_close`. Tests run under AddressSanitizer
  in CI and under valgrind locally without leaks.
- **Text console** (libctru's `PrintConsole`) rather than graphics: simple to
  read and change. Its 8x8 font is code page 437, so `ui_print` converts the
  French accents from UTF-8 (`app/ui.c`).
- **Files**: plain `stdio`. Writes go through a temporary file then a rename;
  the 3DS refuses to rename over an existing file, so the old one is removed
  first (`rs_write_file_atomic`).

### 3DS-specific code (app/)

| File | Role |
| --- | --- |
| `main.c` | services start (romfs, `ps`, `ac`, `soc` with its 1 MiB buffer, curl), first start, main loop |
| `app.c` | actions: pairing, folders, sync of one or all games, choices, settings |
| `ui.c` | two consoles, CP437 conversion, dialogs, system keyboard (`swkbd`) |
| `browser.c` | SD card folder browser |
| `launch.c` | YANBF detection (`am`) and application jump (`APT`) |
| `platform_3ds.c` | hardware random numbers (`ps`), console clock |

## Building

The tests of the core need a C compiler and libcurl's development files
(`libcurl-devel` on Fedora, `libcurl4-openssl-dev` on Debian/Ubuntu):

```sh
make 3ds-test     # unit tests (sanitizers when available)
make 3ds-e2e      # end-to-end test against the real Go server (needs Go)
```

The 3DS app needs devkitPro. Without installing it, use its official image
from the repository root:

```sh
podman run --rm -v "$PWD":/src:Z -w /src/3ds docker.io/devkitpro/devkitarm make
```

`make cia` also needs `makerom` (3DSGuy/Project_CTR) and `bannertool`
(diasurgical fork) in `PATH`; the CI downloads pinned versions (see
`.github/workflows/build-3ds.yml`).

## Not done (yet)

- Nothing of the 3DS layer could be run on a console or an emulator before
  the first release: see `docs/tests-manuels-3ds.md` for the manual tests.
- HTTPS servers: curl is built with mbedtls, but no certificate store is set
  up; use the server's LAN address over HTTP.
- DSiWare saves, ROMs in archives (TWiLight Menu++ does not launch them
  either).
