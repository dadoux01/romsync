# RomSync

Self-hosted save synchronisation for Nintendo DS games.

RomSync keeps one up-to-date save per game and per account on your own server.
Each device pulls the active save before you play and sends it back afterwards,
so you can start a game on a PC emulator, continue it on an Android phone or a
3DS, and come back to the PC without copying files around. Every previous save
stays in the history and can be restored, within a retention policy you choose.

> **Status:** phase 4 of the [roadmap](docs/SPEC.md#dépôt-roadmap-et-questions-ouvertes):
> the server, the web interface, the **desktop client** for Linux (x86-64
> and ARM64), macOS and Windows, with melonDS, DeSmuME and RetroArch
> (melonDS DS), and the **3DS homebrew** (TWiLight Menu++ and nds-bootstrap,
> see [`3ds/README.md`](3ds/README.md)) are usable. Android waits for a tester
> (see `docs/research/android.md`) and iOS is still being studied.

## Features

- **One binary, one volume**: a Go server with SQLite and file storage, the web
  interface embedded in the binary, no external database or cache.
- **No silent overwrite**: when two devices played without syncing, nothing
  is sent or overwritten until you choose which save to keep (yours, or the
  server's while yours stays in the history and in `.backup`). Otherwise the
  most recent save wins. Padding added by an emulator or a flashcard is not a
  difference. A device whose clock runs in the future is detected and its
  dates corrected.
- **History you can tidy up**: old versions can be deleted from the web
  interface (never the active or a pinned one).
- **Full history**: restore, pin and annotate any version; retention policies
  (`all`, last N, last N days, or *smart*: everything for 7 days, one per day
  for 30 days, then one per week), per account and per game.
- **Canonical format**: the server stores the raw content of the save chip;
  saves are converted to and from emulator formats (melonDS `.sav`, DeSmuME
  `.dsv`, RetroArch `.srm`), so one save moves between emulators.
- **Multi-user**: one administrator, other accounts by single-use invitation.
  Devices never see a password: they are paired with a 10-minute code and get
  a revocable token.
- **Manual import/export** in the web interface, for a DS with a flashcard
  (DSTT, R4…) or for troubleshooting.

Not in scope: hosting or distributing ROMs (they stay on your devices), save
states, other consoles.

## Server installation with Docker

Requirements: Docker with Compose, on a machine of your home network. The
server image is published on GitHub's container registry for `linux/amd64`
and `linux/arm64`:

| Tag | Follows |
| --- | --- |
| `ghcr.io/dadoux01/romsync:0.3.0` | exactly this release |
| `ghcr.io/dadoux01/romsync:0.3` | the latest 0.3.x (fixes only) |
| `ghcr.io/dadoux01/romsync:latest` | the latest release |

Get the example compose file and start it:

```sh
mkdir romsync && cd romsync
curl -LO https://raw.githubusercontent.com/dadoux01/romsync/main/deploy/docker-compose.yml
docker compose up -d
```

To update: `docker compose pull && docker compose up -d`. To build the image
yourself instead, clone the repository and run
`docker build -f deploy/Dockerfile -t romsync .` from its root (or
`docker compose build` in `deploy/` after switching to the `build:` section
of the compose file).

> **Package visibility.** A package pushed to ghcr.io is **private** by
> default, even for a public repository: `docker pull` then asks for
> credentials. The owner makes it public once, from GitHub → the profile's
> *Packages* tab → `romsync` → *Package settings* → *Danger Zone* →
> *Change visibility* → *Public*. Alternatively, log in on the server with
> `docker login ghcr.io` and a personal access token with the
> `read:packages` scope.

Open `http://<server-address>:8080` and create the administrator account: the
first-start screen only appears while no account exists. Then:

1. **Invite** other people from *Administration* (single-use link, 7 days).
2. **Pair a device** from *Appareils* → *Ajouter un appareil*: enter the server
   address, the 8-character code and a name on the device.
3. **Import** existing saves (`.sav` or `.dsv`) from *Importer*.

The image is based on distroless (about 16 MB) and runs as a non-root user;
`docker run --rm ghcr.io/dadoux01/romsync:latest version` prints its version.

## Client installation

Download the archive of your system from the
[Releases](https://github.com/dadoux01/romsync/releases) page (`SHA256SUMS`
lists their checksums), then pair the device with the code shown on the
website (*Appareils → Ajouter un appareil*). See
[`client/README.md`](client/README.md) for the emulators and their settings.

- **Linux** (`romsync-<version>-linux-x64.tar.gz` or `-linux-arm64` for
  Fedora Asahi and other ARM64 systems): extract it anywhere and run
  `romsync` inside. It needs GTK 3 and libsecret, present on usual desktops.
  The device token goes to the keyring (GNOME Keyring, KWallet, KeePassXC);
  without one, the app asks before storing it in a 0600 file.
- **macOS** (`romsync-<version>-macos.zip`, Apple Silicon and Intel): unzip
  and move *RomSync.app* to *Applications*. The app is **not signed or
  notarised** yet, so Gatekeeper blocks it the first time:
  - right-click *RomSync.app* → *Open* → *Open*, or open it once, then
    *System Settings* → *Privacy & Security* → *Open Anyway*;
  - or remove the quarantine attribute set by the browser:
    `xattr -dr com.apple.quarantine /Applications/RomSync.app`.

  The device token is stored in the login keychain. As long as the app is
  unsigned, **macOS asks again for access to the keychain after each
  update** (each new build has a new ad-hoc signature): choose *Always
  Allow*.
- **Windows** (`romsync-<version>-windows-x64.zip`): extract the folder and
  run `romsync.exe`. SmartScreen may warn about an unknown publisher: *More
  info* → *Run anyway*. The device token is stored in the Credential Manager
  (*Windows Credentials*, generic credential named `RomSync`).

- **3DS** (`romsync-<version>-3ds.cia`, or `.3dsx` for the Homebrew
  Launcher): install the CIA with FBI. The server must be reachable on the
  local network. See [`3ds/README.md`](3ds/README.md).

**Updates.** From 0.5.0 on, the apps update themselves: they ask your
RomSync server, which relays the GitHub releases (the server itself is
updated with its image: `docker compose pull`, Dockge…). The PC app checks at
start and every 24 hours, the 3DS homebrew at start (both can be turned off,
and checked by hand in the settings). Nothing is installed without your
agreement: the release notes are shown, the files are downloaded and
verified (Ed25519 signature of `SHA256SUMS`, then the SHA-256 of the file;
any mismatch is refused, and an older version is never offered), then the
app installs and restarts when you agree, never during a game or with
uploads pending. If the installation fails, the current version stays and
keeps working. Update the server first, then the apps: an app tells you
when its server is too old for it, or the other way round.

**System tray.** Closing the window keeps RomSync in the system tray (this
can be turned off in the settings): saves of games launched without RomSync
are then uploaded automatically, and a notification tells when a newer save
from another device is waiting. On Linux the icon uses StatusNotifierItem:
KDE Plasma shows it, GNOME needs the *AppIndicator and KStatusNotifierItem
Support* extension, Hyprland and other window managers need a bar with a tray
(e.g. waybar's `tray` module).

### Permissions of `/data`

The server runs as the non-root user **65532:65532** inside the container.
The named volume of the example `docker-compose.yml` gets the right owner
automatically. If you mount a host directory on `/data` instead (a bind
mount, e.g. `./data:/data`), it must belong to that user:

```sh
sudo mkdir -p ./data
sudo chown -R 65532:65532 ./data
```

Otherwise the server stops at startup with an explicit message naming the
directory, the process uid:gid and the `chown` command to run. On SELinux
systems (Fedora…), also add `:Z` to the bind mount (`./data:/data:Z`).

### Configuration

All settings are environment variables:

| Variable | Default | Description |
| --- | --- | --- |
| `ROMSYNC_PORT` | `8080` | HTTP port |
| `ROMSYNC_DATA_DIR` | `/data` | Directory of the SQLite database and of the save files |
| `ROMSYNC_MAX_UPLOAD` | `16777216` | Maximum size of an uploaded save, in bytes |
| `ROMSYNC_TRUSTED_PROXIES` | *(empty)* | Comma-separated IPs or CIDR networks whose `X-Forwarded-For` header is trusted |
| `ROMSYNC_RETENTION_INTERVAL` | `1h` | Period of the retention job |
| `ROMSYNC_UPDATES` | `on` | Relay of the app updates (`off`: no app updates, no banner on the website) |
| `ROMSYNC_UPDATE_REPO` | `dadoux01/romsync` | GitHub repository whose releases are relayed (a fork distributes its own) |
| `ROMSYNC_GITHUB_TOKEN` | *(empty)* | Read-only GitHub token, only for a private repository |
| `ROMSYNC_UPDATE_INTERVAL` | `6h` | Period of the release check |

### Data and backups

The `/data` volume holds everything:

```
/data/romsync.db                  SQLite database (accounts, devices, games, versions)
/data/blobs/<ab>/<sha256>         save contents, named by their SHA-256, deduplicated
/data/updates/<version>/          cache of the relayed release files (can be deleted)
```

To back up, copy the volume. For a consistent copy of the database while the
server runs, use SQLite's `VACUUM INTO` from the host, for example:

```sh
docker run --rm -v romsync_romsync-data:/data -v "$PWD":/backup alpine \
  sh -c 'apk add -q sqlite && sqlite3 /data/romsync.db "VACUUM INTO '"'"'/backup/romsync.db'"'"'" && cp -r /data/blobs /backup/'
```

(The volume name is prefixed by the Compose project name: check it with
`docker volume ls`.)

## Access from outside your home with Tailscale

RomSync is not meant to be exposed directly on the Internet. To reach it from
your phone or laptop away from home, use [Tailscale](https://tailscale.com):
your devices join a private network, and Tailscale provides HTTPS.

**Tailscale on the host.** Install Tailscale on the server, then publish the
service on your tailnet with HTTPS:

```sh
sudo tailscale serve --bg 8080
```

RomSync is then available at `https://<machine>.<tailnet>.ts.net` from every
device of your tailnet. Configure clients with that address.

**Tailscale as a sidecar container.** Alternatively, run Tailscale in a
container that shares RomSync's network namespace; `tailscale serve` then
reaches RomSync on `127.0.0.1`, which you can declare as a trusted proxy:

```yaml
services:
  tailscale:
    image: tailscale/tailscale:latest
    hostname: romsync
    environment:
      TS_AUTHKEY: tskey-auth-...        # an auth key from the Tailscale admin console
      TS_STATE_DIR: /var/lib/tailscale
      TS_SERVE_CONFIG: /config/serve.json
    volumes:
      - tailscale-state:/var/lib/tailscale
      - ./serve.json:/config/serve.json:ro   # HTTPS :443 → http://127.0.0.1:8080
    ports:
      - "8080:8080"                      # LAN access (3DS)
  romsync:
    network_mode: service:tailscale
    environment:
      ROMSYNC_TRUSTED_PROXIES: 127.0.0.1
    # ...rest of the romsync service, without "ports"
```

with `serve.json`:

```json
{
  "TCP": { "443": { "HTTPS": true } },
  "Web": {
    "${TS_CERT_DOMAIN}:443": { "Handlers": { "/": { "Proxy": "http://127.0.0.1:8080" } } }
  }
}
```

**About `ROMSYNC_TRUSTED_PROXIES`.** Login and pairing are rate limited per
client IP (5 attempts per minute). Behind a proxy, every request comes from
the proxy's address; RomSync only reads `X-Forwarded-For` (and
`X-Forwarded-Proto`, to mark the session cookie `Secure`) when the request
comes from an address listed in this variable. Leaving it empty is safe: all
clients going through the proxy then simply share one rate-limit bucket. Only
list an address that untrusted clients cannot connect from.

**3DS.** Tailscale does not exist on the 3DS: the 3DS must reach the server on
your local network (`http://<lan-address>:8080`), so keep the port published.

## Repository layout

```
server/    Go server: API, storage, retention, single binary
web/       web interface (Svelte 5 + Vite), compiled then embedded in server/
client/    Flutter desktop client: Linux, macOS, Windows (see client/README.md)
3ds/       3DS homebrew in C (devkitPro), see 3ds/README.md
profiles/  declarative save conversion profiles, shared by the clients
api/       OpenAPI specification of the REST API
deploy/    Dockerfile and docker-compose.yml
docs/      specification
```

The [specification](docs/SPEC.md) (in French) describes the data model, the
sync protocol and the API; [`api/openapi.yaml`](api/openapi.yaml) documents
every route.

## Development

See [CONTRIBUTING.md](CONTRIBUTING.md). In short, with Go 1.27+, Node.js 24
and Flutter 3.47+:

```sh
make test         # Go tests, svelte-check, web tests and client tests
make build        # server/bin/romsync with the web interface embedded
make 3ds-test     # tests of the 3DS homebrew's C core (needs libcurl headers)
make dev-server   # API on :8080 (data in ./data)
make dev-web      # web interface with hot reload on :5173
```

## License

RomSync is free software under the [GNU Affero General Public License v3.0](LICENSE).
If you modify it and offer it as a hosted service, you must publish your changes.

### Third-party code and data

The 3DS homebrew includes [cJSON](https://github.com/DaveGamble/cJSON) (MIT)
and [Monocypher](https://monocypher.org) 4.0.2 (CC0 or BSD-2-Clause, Ed25519
verification of the updates); the PC app uses
[pinenacl](https://pub.dev/packages/pinenacl) (MIT) for the same purpose.


`server/internal/chipdb/chipsizes.txt`, the save size of about 6,700 DS games,
is extracted from [melonDS](https://github.com/melonDS-emu/melonDS)'s ROM list
(`src/ROMList.cpp`, © melonDS team, GPL-3.0-or-later), which section 13 of the
AGPL-3.0 allows to combine with RomSync.
