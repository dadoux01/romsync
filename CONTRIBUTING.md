# Contributing to RomSync

Thanks for your interest! Bug reports, emulator profiles, fixes and
documentation are all welcome.

## Before you start

- [`docs/SPEC.md`](docs/SPEC.md) is the reference for the behaviour of
  RomSync. If a change departs from it, open an issue first so the
  specification can be discussed and updated in the same pull request.
- Bigger changes (new feature, API change) deserve an issue before the code.

## Development environment

You need:

- Go 1.27 or later
- Node.js 24 and npm
- Flutter 3.47 or later for the client (see [`client/README.md`](client/README.md))
- for the 3DS homebrew: a C compiler and libcurl's development files (tests of
  the core), and devkitPro or its Docker image (build), see
  [`3ds/README.md`](3ds/README.md)
- optionally golangci-lint v2 and Docker or Podman

```sh
make test         # Go tests (race detector), svelte-check, web unit tests
make lint         # golangci-lint (server/.golangci.yml)
make build        # server/bin/romsync with the web interface embedded
```

To work on the interface with hot reload, run the API and Vite side by side:

```sh
make dev-server   # API on :8080, data in ./data
make dev-web      # http://localhost:5173, /api proxied to :8080
```

Building the Docker image (from the repository root):

```sh
docker build -f deploy/Dockerfile -t romsync .
```

## Project layout

| Path | Content |
| --- | --- |
| `server/cmd/romsync` | Entry point |
| `server/internal/api` | HTTP handlers, authentication, routes (`routes.go`) |
| `server/internal/syncrule` | "Most recent wins" rule and clock correction |
| `server/internal/retention` | Retention policies and periodic job |
| `server/internal/convert` | Save format conversions (raw, DeSmuME) |
| `server/internal/blobs` | Content-addressed file storage |
| `server/internal/db` | SQLite and migrations (`migrations/NNNN_name.sql`) |
| `web/src` | Svelte interface (`pages/`, `components/`, `lib/`) |
| `client/packages/romsync_core` | Client logic in pure Dart (sync engine, API client, profiles…) |
| `client/app` | Flutter interface of the client |
| `3ds/core` | Portable C core of the 3DS homebrew (same decisions as `romsync_core`) |
| `3ds/app` | 3DS layer (libctru): screens, keyboard, network, launch |
| `3ds/tests` | Unit and end-to-end tests of the C core, on Linux |
| `profiles/` | Declarative conversion profiles |
| `api/openapi.yaml` | API specification |

## Rules of thumb

- **Tests first-class**: every change to the server comes with tests. API
  behaviour is covered by integration tests (`server/internal/api/*_test.go`)
  that run a real server on a temporary database.
- **API changes** must update `api/openapi.yaml` in the same commit;
  `TestOpenAPICoversRoutes` fails when a route is missing from it, and CI lints
  the file with Redocly.
- **Database changes** go in a new migration file
  (`server/internal/db/migrations/NNNN_description.sql`); never edit a
  migration that has been released.
- **Errors** use the single format `{"error": {"code", "message"}}` with the
  codes listed in the specification.
- **No new heavy dependency** without discussion: the server is a single
  static binary, the web interface has no runtime dependency besides Svelte.
- Run `gofmt`/`goimports`; the web code is type-checked with `svelte-check`.
- **Sync decisions** live in two places, `romsync_core` (Dart) and `3ds/core`
  (C): change both, with the same test case on each side.

## Adding an emulator profile

A profile describes how an emulator stores a DS save compared to the raw
content of the save chip (see [`profiles/README.md`](profiles/README.md)):

1. Add `profiles/<id>.json` with `"status": "to_verify"`, then run
   `client/tool/sync_profiles.sh` so that the client bundles it (the 3DS
   build copies the profiles into its romfs by itself).
2. If the server must offer it for import/export, implement it in
   `server/internal/convert` and register it; `TestProfilesMatchCode` checks
   that the JSON and the code agree.
3. Add a round-trip test with a reference save — preferably produced by the
   emulator itself from a freely redistributable homebrew. Do not commit saves
   of commercial games.
4. Switch the status to `confirmed` once the round trip has been verified with
   the real emulator.

## Commits and pull requests

- Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/):
  `feat(server): …`, `fix(web): …`, `docs: …`, `test: …`, `ci: …`,
  `build(deploy): …`, `refactor: …`.
- Keep each commit focused and with tests passing.
- CI must be green: lint, tests, web build, OpenAPI lint and Docker build.
- GitHub Actions are pinned by commit SHA (Dependabot keeps them up to date);
  never interpolate `${{ … }}` values that come from inputs or events inside
  `run:` scripts, pass them through `env:`.

## Releases

Releases are published from `v*` tags; `SHA256SUMS` is signed with the
release key. The steps, the signing key and the repository protections are
described (in French) in [`docs/releasing.md`](docs/releasing.md).

## License

By contributing, you agree that your contributions are licensed under the
[AGPL-3.0](LICENSE), like the rest of the project.
