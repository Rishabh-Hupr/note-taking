#!/usr/bin/env bash
# Butler — build the Go sidecar + Swift overlay into test-build/, then launch the app
# in the background. Safe to re-run: it stops any running instance first, so you
# always end up with exactly one fresh build running.
# Usage: ./test-butler.sh   (from a checkout of this repo)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_DIR="$ROOT/go-rewrite"
APP_DIR="$ROOT/macos-app"
TEST_BUILD_DIR="$ROOT/test-build"           # both built artifacts are delivered here
CORE_BIN="$TEST_BUILD_DIR/butler-core"
# Temp build target. Deliberately does NOT contain "butler-core": the reload
# kills the sidecar with pkill, and a substring name (e.g. butler-core.new) would
# make that pkill also match an in-flight `go build -o …` process.
CORE_TMP="$TEST_BUILD_DIR/.core-build.tmp"
APP_BIN="$TEST_BUILD_DIR/Butler"
# In this test harness the data dir is the build dir, so runs stay self-contained
# (separate from a real ~/.butler). launch_app exports this as BUTLER_DATA_DIR.
DATA_DIR="$TEST_BUILD_DIR"

# Persistent Swift module cache. Compiling the AppKit/Foundation Clang modules is
# the bulk of a Swift build (~22s); a shared cache reused across builds drops an
# incremental Swift rebuild to ~1s. Kept outside .build so `swift package clean`
# and manual .build wipes don't throw it away.
MODULE_CACHE="${BUTLER_MODULE_CACHE:-$HOME/.cache/butler-swift-modulecache}"

# --- flags -------------------------------------------------------------------
# --core-only (-c): rebuild just the Go sidecar and hot-swap it into the running
# app — no Swift build, no app restart. The app's SidecarClient watchdog respawns
# the core from BUTLER_CORE_BIN the moment the old process exits, so it picks up
# the fresh binary automatically. Falls back to a full build+launch if the app
# isn't running yet. Ideal for: gnther go-rewrite "./test-butler.sh --core-only"
CORE_ONLY=0
case "${1:-}" in
    -go|--go|-be|--be|--backend|-c|--core-only) CORE_ONLY=1 ;;
esac

# --- prerequisites -----------------------------------------------------------
command -v go >/dev/null 2>&1 || {
    echo "error: 'go' not found. Install Go (e.g. 'brew install go' or 'mise use -g go@latest')." >&2
    exit 1
}
command -v swift >/dev/null 2>&1 || {
    echo "error: 'swift' not found. Install Xcode Command Line Tools: 'xcode-select --install'." >&2
    exit 1
}

mkdir -p "$TEST_BUILD_DIR"

# Launch the (already-built) app in the background, wired to the current CORE_BIN.
launch_app() {
    mkdir -p "$DATA_DIR"
    export BUTLER_CORE_BIN="$CORE_BIN"
    # Explicit so the sidecar uses the same dir we log to (not a matching default).
    export BUTLER_DATA_DIR="$DATA_DIR"
    "$APP_BIN" >"$DATA_DIR/butler-ui.log" 2>&1 &
    local pid=$!
    disown "$pid" 2>/dev/null || true
    cat <<EOF

✔ Butler is running in the background (PID $pid). Your terminal is free.
  • Summon:  ⌘⌥F to search   ·   ⌘⌥P to add a note
  • Stop:    kill $pid        (or: pkill -f "$APP_BIN")
  • Build:   $TEST_BUILD_DIR (butler-core + Butler)
  • Logs:    $DATA_DIR/butler-ui.log   ·   data: $DATA_DIR
EOF
}

# --- build the Go sidecar → build/butler-core --------------------------------
# GOPROXY=direct fetches modules straight from source (mattn/go-sqlite3), needed
# where the public Go proxy is blocked. cgo + the sqlite_fts5 tag are mandatory.
# Build to a temp path then atomically rename over CORE_BIN: overwriting the file
# in place while the app runs it fails with "text file busy", and rename lets the
# running process keep its old inode until we kill it.
echo "==> Building Go sidecar → $CORE_BIN"
(
    cd "$CORE_DIR"
    CGO_ENABLED=1 GOPROXY="${GOPROXY:-direct}" GOSUMDB="${GOSUMDB:-off}" \
        go build -tags sqlite_fts5 -o "$CORE_TMP" .
)
mv -f "$CORE_TMP" "$CORE_BIN"

# --- backend-only: Go is built (above); never touch Swift. Hot-swap into the
# running app if there is one, otherwise just leave the fresh binary in place.
if [[ "$CORE_ONLY" == 1 ]]; then
    if pgrep -f "$APP_BIN" >/dev/null 2>&1; then
        echo "==> Reloading sidecar in the running app (watchdog will respawn it)…"
        pkill -f "^${CORE_BIN}$" || true   # exact match only; app's SidecarClient relaunches the fresh binary
        echo "✔ Backend reloaded — app kept running, Swift untouched."
    else
        echo "✔ Backend built. Run ./test-butler.sh (no flag) to build the UI and launch."
    fi
    exit 0
fi

# --- build the Swift overlay → build/Butler ----------------------------------
# -c release for a shippable binary; module-cache-path makes the AppKit/Foundation
# module compilation reusable across builds (see MODULE_CACHE note above).
echo "==> Building Swift overlay → $APP_BIN"
mkdir -p "$MODULE_CACHE"
( cd "$APP_DIR" && swift build -c release -Xswiftc -module-cache-path -Xswiftc "$MODULE_CACHE" )
cp "$APP_DIR/.build/release/Butler" "$APP_BIN"

# --- stop any existing instance (idempotent: converge to one fresh instance) --
if pgrep -f "$APP_BIN" >/dev/null 2>&1; then
    echo "==> Stopping the running Butler instance…"
    pkill -f "$APP_BIN" || true
    sleep 1
fi

# --- launch in the background ------------------------------------------------
launch_app
