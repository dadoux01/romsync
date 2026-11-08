#!/bin/sh
# Runs tests/e2e.c against the real RomSync server: builds the Go server,
# starts it in a temporary folder, creates the administrator and two
# pairing codes with curl, then runs the test.
#
#   e2e.sh <path of the e2e binary>
set -eu

e2e_bin=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)

# Go: $GO, then ~/.local/go (the system one may be gccgo), then PATH.
go=${GO:-}
[ -z "$go" ] && [ -x "$HOME/.local/go/bin/go" ] && go=$HOME/.local/go/bin/go
[ -z "$go" ] && go=$(command -v go || true)
[ -n "$go" ] || { echo "e2e: Go is needed" >&2; exit 1; }

work=$(mktemp -d "${TMPDIR:-/tmp}/romsync-3ds-e2e-XXXXXX")
server_pid=
cleanup() {
    [ -n "$server_pid" ] && kill "$server_pid" 2>/dev/null || true
    rm -rf "$work"
}
trap cleanup EXIT INT TERM

(cd "$repo/server" && CGO_ENABLED=0 "$go" build -o "$work/romsync-server" ./cmd/romsync)

# A free port chosen by the system.
port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')
url="http://127.0.0.1:$port"
ROMSYNC_PORT=$port ROMSYNC_DATA_DIR="$work/data" ROMSYNC_UPDATES=off "$work/romsync-server" >"$work/server.log" 2>&1 &
server_pid=$!

i=0
until curl -fs "$url/healthz" >/dev/null; do
    i=$((i + 1))
    if [ $i -gt 100 ]; then
        echo "e2e: the server did not start" >&2
        cat "$work/server.log" >&2
        exit 1
    fi
    sleep 0.1
done

jar="$work/cookies"
curl -fs -c "$jar" -H 'Content-Type: application/json' \
    -d '{"username":"admin","password":"admin-password"}' "$url/api/v1/setup" >/dev/null
code() {
    curl -fs -b "$jar" -X POST "$url/api/v1/pair-codes" |
        python3 -c 'import json,sys; print(json.load(sys.stdin)["code"])'
}
code1=$(code)
code2=$(code)

"$e2e_bin" "$url" "$code1" "$code2" "$work" || {
    echo "--- server log ---" >&2
    tail -n 30 "$work/server.log" >&2
    exit 1
}
