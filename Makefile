# RomSync build helpers. `make build` produces server/bin/romsync with the web
# interface embedded.

WEBUI_DIST := server/internal/webui/dist
GO ?= go

.PHONY: all build web embed server test test-go test-web check lint dev-server dev-web clean

all: build

build: embed server

web:
	cd web && npm ci && npm run build

# Copy the compiled web UI where go:embed picks it up.
embed: web
	find $(WEBUI_DIST) -mindepth 1 ! -name .gitkeep -delete
	cp -r web/dist/. $(WEBUI_DIST)/

server:
	cd server && CGO_ENABLED=0 $(GO) build -trimpath -ldflags="-s -w" -o bin/romsync ./cmd/romsync

test: test-go test-web

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

clean:
	rm -rf server/bin web/dist
	find $(WEBUI_DIST) -mindepth 1 ! -name .gitkeep -delete
