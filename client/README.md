# RomSync client

Desktop client of RomSync: it finds your DS ROMs, launches them in melonDS and
syncs their saves with your RomSync server around each game. Phase 2 of the
roadmap: **Linux only, melonDS only** (DeSmuME, macOS, Windows and Android come
later).

## What it does

- **Pairing**: server address, the 8-character code shown on the website
  (*Appareils → Ajouter un appareil*) and a device name. The device token is
  stored in the system keyring (Secret Service through libsecret: GNOME
  Keyring, KWallet, KeePassXC…). Without a keyring — common on Hyprland or
  other minimal sessions — pairing stops and offers to store the token in a
  file with 0600 permissions instead, with a warning.
- **Library**: one or more ROM folders, scanned recursively for `.nds` files,
  including inside `.zip` (read directly) and `.7z` archives (read with the
  `7z`, `7zz` or `7za` program: install `p7zip` or `7zip`). Games are
  identified by the code in the ROM header, or `h:<sha1>` for homebrew.
- **ROMs sharing a game code** (patched ROMs, translations, hacks): the list
  flags them and asks, once per ROM, whether it *shares* the save of the game
  or is *separated* under a forced `x:` identifier you name. Until you answer,
  these ROMs are not synced.
- **Save states in the list**: up to date, to upload, to download, offline,
  choice required, and "conflit résolu automatiquement".
- **Playing**: before launching, the client sends queued uploads, uploads a
  save changed outside a sync, downloads a newer server save (the replaced
  local save is copied to a `.backup` folder next to it; 10 copies kept per
  save by default). During the game, each in-game save is uploaded after 5 s
  without writes; a last upload happens when melonDS exits.
- **Offline**: the game still launches, with a warning. Uploads wait in a
  queue on disk and leave as soon as the server answers; each keeps the same
  upload id across retries and restarts, so nothing is duplicated.
- **History**: read-only list of a game's versions, with a link to the
  website to restore one.

The client never cuts a save: it only removes the emulator's header or footer
(none for melonDS) and sends the raw save; size normalisation is the
server's job.

## melonDS

Settings → melonDS:

- **Executable**: a name looked up in `PATH` (`melonDS`) or a full path, e.g.
  the extracted AppImage.
- **Flatpak**: `flatpak run net.kuribo64.melonDS`. The Flatpak only has access
  to your home folder by default; for ROMs elsewhere (another disk, `/mnt`,
  `/run/media`…), the client shows the command to run, for example:

  ```sh
  flatpak override --user --filesystem=/mnt/games/nds net.kuribo64.melonDS
  ```

- **Save folder**: detected from melonDS's configuration (`SaveFilePath` in
  `~/.config/melonDS/melonDS.toml`, or
  `~/.var/app/net.kuribo64.melonDS/config/melonDS/melonDS.toml` for the
  Flatpak). Empty means next to the ROM, which is melonDS's default; you can
  force another folder.

## Files

| Path | Content |
| --- | --- |
| `~/.config/romsync/config.json` | Server, ROM folders, melonDS settings, per-ROM choices |
| `~/.config/romsync/token` | Device token, only if you chose file storage (0600) |
| `~/.local/share/romsync/state.json` | Sync state per save file |
| `~/.local/share/romsync/queue/` | Uploads waiting for the server (and `failed/` for refused ones) |
| `<save folder>/.backup/` | Local saves replaced by a download |

`XDG_CONFIG_HOME` and `XDG_DATA_HOME` are honoured.

## Building

Requirements on Fedora:

```sh
sudo dnf install clang cmake ninja-build pkgconf-pkg-config gtk3-devel libsecret-devel p7zip
```

Flutter 3.47 or later:

- **x86-64**: download the Linux archive from flutter.dev and add `flutter/bin`
  to `PATH`.
- **ARM64 (Fedora Asahi…)**: Flutter only publishes x64 archives; install it
  with git, the tool then downloads the ARM64 engine itself:

  ```sh
  git clone --depth 1 --branch 3.47.9 https://github.com/flutter/flutter.git ~/.local/flutter
  ```

  The ARM64 build must run on an ARM64 machine: Flutter cannot cross-compile
  Linux desktop apps from x86-64. CI builds both architectures on native
  runners.

Then, from the repository root:

```sh
make client-test    # analyze + unit tests (romsync_core and app)
make client-e2e     # end-to-end tests against the real Go server (needs Go)
make client-build   # client/app/build/linux/<arch>/release/bundle/romsync
```

`make client-build` first copies `profiles/*.json` into the app's assets
(`client/tool/sync_profiles.sh`); a test fails if the copies are stale.

## Layout

```
client/
├── packages/romsync_core/   pure Dart: API client, NDS headers, archives, profiles,
│                            local state, upload queue, sync engine, emulator profiles
├── app/                     Flutter interface (Linux)
└── tool/sync_profiles.sh    copies profiles/ into the app's assets
```

`romsync_core` has no Flutter dependency and is tested with `dart test`; the
end-to-end tests (`dart test -t e2e`) build and start the real server.
