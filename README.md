# Butler

A lightning-fast, keyboard-powered note utility for macOS — store and retrieve
notes or code snippets as simple key→value pairs, summoned from anywhere with a
global hotkey. A minimalist, Spotlight-style knowledge base.

- **⌘⌥F** — search: type to filter (matches keys **and** values), ↑/↓ to move,
  **Enter** to copy the selected note to the clipboard, **Esc**/click-away to dismiss.
- **⌘⌥P** — add a note: type a **Key** and **Value**, **Enter** to save
  (**⌘Return** for a newline in the value), **Esc** to cancel.

Notes are stored in `~/.butler/notes.db` (override with `BUTLER_DATA_DIR`).

## Architecture

Butler is two processes: a native Swift overlay and a Go data sidecar.

```
┌──────────────────────────┐   newline-delimited JSON    ┌───────────────────────┐
│  macos-app/ (Swift/AppKit)│  over stdin/stdout (pipes)  │ go-rewrite/ (Go)      │
│  • resident agent (hotkey)│ ───── put/fetch/list ─────▶ │ • SQLite + FTS5 store │
│  • borderless NSPanel     │ ◀──── {ok, notes, …} ────── │ • ~/.butler/notes.db  │
│  • NSVisualEffectView blur│                             │ • resident sidecar    │
└──────────────────────────┘                             └───────────────────────┘
```

The Swift app launches the Go binary (`butler-core`) once at startup and talks to
it over pipes — the sidecar stays resident with the DB open, so summoning and
searching are instant (no per-keystroke process spawn). Search uses SQLite's FTS5
full-text index over both key and value.

## Repository layout

```
.
├── launch-butler.sh  # build both halves and launch the app (backgrounded)
├── go-rewrite/     # Go sidecar: SQLite/FTS5 store + stdio JSON protocol
│   ├── main.go         # stdio loop (ping/put/fetch/list)
│   ├── dao/            # Note model + queries (fetch, put)
│   └── setup_database.go
└── macos-app/      # Swift/AppKit overlay (SwiftPM package)
    └── Sources/Butler/ # AppDelegate, panels, SidecarClient, hotkey, view controllers
```

Earlier implementations live on their own branches: **`python`** (the original
Python CLI) and **`failedWailsApproach`** (an abandoned Wails/React attempt).

## Prerequisites

- macOS 13+ (Apple Silicon or Intel)
- **Xcode Command Line Tools** (`xcode-select --install`) — provides Swift and cgo
- **Go** (`brew install go`, or `mise use -g go@latest`)
- Network access on first build to fetch `mattn/go-sqlite3` (the script uses
  `GOPROXY=direct`, which pulls from GitHub directly if the public Go proxy is blocked)

## Quick start

```bash
git clone https://github.com/Rishabh-Hupr/note-taking.git
cd note-taking
./launch-butler.sh
```

`launch-butler.sh` builds the Go sidecar and the Swift overlay (release), then
launches the app **in the background** and frees your terminal. It prints the
PID and how to stop it (`kill <PID>` / `pkill`). Re-running is safe — it stops
any running instance first, so you always get one fresh build. Then press
**⌘⌥F** or **⌘⌥P**.

## Manual build

```bash
# Go sidecar
cd go-rewrite
CGO_ENABLED=1 GOPROXY=direct GOSUMDB=off go build -tags sqlite_fts5 -o butler-core .

# Swift overlay (run from source)
cd ../macos-app
BUTLER_CORE_BIN="$(cd ../go-rewrite && pwd)/butler-core" swift run
```

Run the backend tests with the FTS5 build tag:

```bash
cd go-rewrite && go test -tags sqlite_fts5 ./...
```

## Status

MVP: search, copy, and add-note all work end to end. Not yet packaged as a
double-click `.app` — it currently runs from source via `run.sh`. Planned next:
a signed `.app` bundle with a login item (auto-resident), plus a delete action.
