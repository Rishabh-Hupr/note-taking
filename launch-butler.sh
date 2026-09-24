#!/usr/bin/env bash
# Butler — build the Go sidecar + Swift overlay into build/, then launch the app
# in the background. Safe to re-run: it stops any running instance first, so you
# always end up with exactly one fresh build running.
# Usage: ./launch-butler.sh   (from a checkout of this repo)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_DIR="$ROOT/go-rewrite"
APP_DIR="$ROOT/macos-app"
BUILD_DIR="$ROOT/build"          # both built artifacts are delivered here
CORE_BIN="$BUILD_DIR/butler-core"
APP_BIN="$BUILD_DIR/Butler"
DATA_DIR="${BUTLER_DATA_DIR:-$HOME/.butler}"

# --- prerequisites -----------------------------------------------------------
command -v go >/dev/null 2>&1 || {
    echo "error: 'go' not found. Install Go (e.g. 'brew install go' or 'mise use -g go@latest')." >&2
    exit 1
}
command -v swift >/dev/null 2>&1 || {
    echo "error: 'swift' not found. Install Xcode Command Line Tools: 'xcode-select --install'." >&2
    exit 1
}

mkdir -p "$BUILD_DIR"

# --- build the Go sidecar → build/butler-core --------------------------------
# GOPROXY=direct fetches modules straight from source (mattn/go-sqlite3), needed
# where the public Go proxy is blocked. cgo + the sqlite_fts5 tag are mandatory.
echo "==> Building Go sidecar → build/butler-core"
(
    cd "$CORE_DIR"
    CGO_ENABLED=1 GOPROXY="${GOPROXY:-direct}" GOSUMDB="${GOSUMDB:-off}" \
        go build -tags sqlite_fts5 -o "$CORE_BIN" .
)

# --- build the Swift overlay → build/Butler ----------------------------------
echo "==> Building Swift overlay → build/Butler"
( cd "$APP_DIR" && swift build -c release )
cp "$APP_DIR/.build/release/Butler" "$APP_BIN"

# --- stop any existing instance (idempotent: converge to one fresh instance) --
if pgrep -f "$APP_BIN" >/dev/null 2>&1; then
    echo "==> Stopping the running Butler instance…"
    pkill -f "$APP_BIN" || true
    sleep 1
fi

# --- launch in the background ------------------------------------------------
mkdir -p "$DATA_DIR"
export BUTLER_CORE_BIN="$CORE_BIN"
# Explicit so the sidecar uses the same dir we log to (not a matching default).
export BUTLER_DATA_DIR="$DATA_DIR"
"$APP_BIN" >"$DATA_DIR/butler-ui.log" 2>&1 &
APP_PID=$!
disown "$APP_PID" 2>/dev/null || true

cat <<EOF

✔ Butler is running in the background (PID $APP_PID). Your terminal is free.
  • Summon:  ⌘⌥F to search   ·   ⌘⌥P to add a note
  • Stop:    kill $APP_PID        (or: pkill -f "$APP_BIN")
  • Build:   $BUILD_DIR (butler-core + Butler)
  • Logs:    $DATA_DIR/butler-ui.log   ·   data: $DATA_DIR
EOF
