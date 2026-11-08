# RomSync build helpers. `make build` produces server/bin/romsync with the web
# interface embedded.

WEBUI_DIST := server/internal/webui/dist
GO ?= go
VERSION ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo dev)

.PHONY: all build web embed server test test-go test-web check lint dev-server dev-web clean \
	client-profiles client-test client-e2e client-build 3ds-test 3ds-e2e

all: build

build: embed server

web:
	cd web && npm ci && npm run build

# Copy the compiled web UI where go:embed picks it up.
embed: web
	find $(WEBUI_DIST) -mindepth 1 ! -name .gitkeep -delete
	cp -r web/dist/. $(WEBUI_DIST)/

server:
	cd server && CGO_ENABLED=0 $(GO) build -trimpath -ldflags="-s -w -X main.version=$(VERSION)" -o bin/romsync ./cmd/romsync

test: test-go test-web client-test

test-go:
	cd server && $(GO) test -race ./...

test-web:
	cd web && npm run check && npm test

lint:
	cd server && golangci-lint run ./...

# Development: run both in two terminals, then open http://localhost:5173.
dev-server:
	cd server && ROMSYNC_DATA_DIR=../data $(GO) run ./cmd/romsync

dev-web:
	cd web && npm run dev

# Client (Flutter, Linux). Needs Flutter in PATH; the end-to-end tests also
# need Go.
client-profiles:
	client/tool/sync_profiles.sh

client-test:
	cd client && flutter pub get && flutter analyze
	cd client/packages/romsync_core && dart test -x e2e
	cd client/packages/romsync_updater && dart test
	cd client/app && flutter test

client-e2e:
	cd client/packages/romsync_core && dart test -t e2e

# 3DS homebrew: tests of the portable C core on Linux (needs a C compiler
# and libcurl's development files).
3ds-test:
	$(MAKE) -C 3ds/tests

# End-to-end test of the C core against the real server (also needs Go).
3ds-e2e:
	$(MAKE) -C 3ds/tests e2e

client-build: client-profiles
	cd client/app && flutter build linux --release

clean:
	rm -rf server/bin web/dist
	find $(WEBUI_DIST) -mindepth 1 ! -name .gitkeep -delete
