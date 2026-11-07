# RomSync

Self-hosted save synchronisation for Nintendo DS games.

RomSync keeps one up-to-date save per game and per account on your own server.
Each device pulls the active save before you play and sends it back afterwards,
so you can start a game on a PC emulator, continue it on an Android phone or a
3DS, and come back to the PC without copying files around. Every previous save
stays in the history and can be restored, within a retention policy you choose.

> **Status:** phase 2 of the [roadmap](docs/SPEC.md#dépôt-roadmap-et-questions-ouvertes):
> the server, the web interface and the **Linux desktop client** (melonDS,
> x86-64 and ARM64) are usable. DeSmuME, macOS, Windows, Android and the 3DS
> homebrew come in the next phases.

## Features

- **One binary, one volume**: a Go server with SQLite and file storage, the web
  interface embedded in the binary, no external database or cache.
- **Most recent save wins**: when two devices diverge, the save made last
  becomes active and the other one stays in the history, flagged as a conflict.
  A device whose clock runs in the future is detected and its dates corrected.
- **Full history**: restore, pin and annotate any version; retention policies
  (`all`, last N, last N days, or *smart*: everything for 7 days, one per day
  for 30 days, then one per week), per account and per game.
- **Canonical format**: the server stores the raw content of the save chip;
  saves are converted to and from emulator formats (DeSmuME `.dsv` today).
- **Multi-user**: one administrator, other accounts by single-use invitation.
  Devices never see a password: they are paired with a 10-minute code and get
  a revocable token.
- **Manual import/export** in the web interface, for a DS with a flashcard
  (DSTT, R4…) or for troubleshooting.

Not in scope: hosting or distributing ROMs (they stay on your devices), save
states, other consoles.

## Installation with Docker

Requirements: Docker with Compose, on a machine of your home network.

```sh
git clone https://github.com/dadoux01/romsync.git
cd romsync/deploy
docker compose up -d
```

Open `http://<server-address>:8080` and create the administrator account: the
first-start screen only appears while no account exists. Then:

1. **Invite** other people from *Administration* (single-use link, 7 days).
2. **Pair a device** from *Appareils* → *Ajouter un appareil*: enter the server
   address, the 8-character code and a name on the device.
3. **Import** existing saves (`.sav` or `.dsv`) from *Importer*.

The image is built locally from `deploy/Dockerfile` (multi-stage build, final
image based on distroless, about 16 MB, running as a non-root user).

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

### Data and backups

The `/data` volume holds everything:

```
/data/romsync.db                  SQLite database (accounts, devices, games, versions)
/data/blobs/<ab>/<sha256>         save contents, named by their SHA-256, deduplicated
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
client/    Flutter client — Linux with melonDS today (see client/README.md)
3ds/       3DS homebrew in C (devkitPro) — coming soon
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
make dev-server   # API on :8080 (data in ./data)
make dev-web      # web interface with hot reload on :5173
```

## License

RomSync is free software under the [GNU Affero General Public License v3.0](LICENSE).
If you modify it and offer it as a hosted service, you must publish your changes.

### Third-party data

`server/internal/chipdb/chipsizes.txt`, the save size of about 6,700 DS games,
is extracted from [melonDS](https://github.com/melonDS-emu/melonDS)'s ROM list
(`src/ROMList.cpp`, © melonDS team, GPL-3.0-or-later), which section 13 of the
AGPL-3.0 allows to combine with RomSync.
