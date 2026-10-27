# Butler

A lightning-fast, keyboard-powered note utility for macOS — store and retrieve
notes or code snippets as simple key→value pairs, summoned from anywhere with a
global hotkey. A minimalist, Spotlight-style knowledge base.

- **⌘⌥F** — search: type to filter (matches keys **and** values), ↑/↓ to move,
  **Enter** to copy the selected note to the clipboard, **⌘D** to delete it
  (a short "Deleted" confirmation shows at the bottom), **Esc**/click-away to
  dismiss. A selected note of up to 8 lines expands to show its text; a longer
  one stays one line and opens in a side preview instead (scrollable past 50
  lines).
- **⌘⌥P** — add a note: type a **Key** and **Value**, **⌘Return** to save
  (**Enter** inserts a newline in the value), **Esc** to cancel. A green "Saved"
  tick confirms it. Leading/trailing spaces and blank lines are trimmed.

The 📒 menu-bar icon briefly shows `📒 last note 3h ago` every 2 hours as a nudge to
capture something. Change how often (or turn it off) from **📒 → Last-Note Reminder**;
`BUTLER_HINT_INTERVAL=<seconds>` overrides it for testing.

Both windows can be dragged anywhere and reopen where you left them. Search shows
up to 200 notes at a time (most recent first); type to find older ones.

Notes are stored in `~/.butler/notes.db` (override with `BUTLER_DATA_DIR`). They're
backed up automatically to `~/.butler/backups/`, and the database is tidied up at
the same time. [RUNBOOK.md](RUNBOOK.md) has the schedule and the restore steps.

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
│   ├── main.go         # stdio loop (ping/put/fetch/delete/list)
│   ├── dao/            # Note model + queries (fetch, put, delete)
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
PID and how to stop it (`kill <PID>` / `pkill`). Re-running is safe — it first
stops any Butler running from this repo (`build/`, `test-build/` or a `swift run`)
and prints which PIDs it stopped, so you always end up with one fresh build. Then press
**⌘⌥F** or **⌘⌥P**.

## Manual build

Both artifacts are delivered into `build/` at the repo root (git-ignored), never
into the source dirs.

```bash
mkdir -p build

# Go sidecar → build/butler-core
(cd go-rewrite && CGO_ENABLED=1 GOPROXY=direct GOSUMDB=off \
  go build -tags sqlite_fts5 -o ../build/butler-core .)

# Swift overlay → build/Butler
(cd macos-app && swift build -c release)
cp macos-app/.build/release/Butler build/Butler

# run (the app finds build/butler-core as its sibling)
./build/Butler
```

## Tests

```bash
cd go-rewrite && CGO_ENABLED=1 go test -tags sqlite_fts5 ./...   # Go backend
cd macos-app && swift test                                       # macOS app (Swift Testing)
```

For a fast edit-and-run loop use `./test-butler.sh` (debug build into
`test-build/`, ~2s Swift rebuilds; `--go` rebuilds and hot-swaps just the backend).

Each request logs its latency to `butler-ui.log` (`~/.butler/`, or `test-build/` under
`test-butler.sh`):
```
⏱ id=7 cmd=fetch notes=200 bytes=81234 roundtrip=3.1ms processing=0.6ms total=3.7ms
```
Logs live in the data dir: `app.log` (backend) and `butler-ui.log` (app). Each rolls
over at 1MB and keeps 3 backups (`.1`–`.3`); they're readable only by you and never
contain note text. Deleting a log while Butler runs is fine — it starts a fresh one
within a few seconds.

`roundtrip` = request sent → full reply received (pipe + backend); `processing` =
reply → decoded for the UI. Each ⌘⌥F also logs how long opening took (format):
```
⏱ open show=<ms> prepare=<ms> firstFrame=<ms> total=<ms>
```

## How data flows
See [DATA_FLOW.md](DATA_FLOW.md) for Mermaid diagrams of every flow: the components,
the wire protocol, opening search, typing, saving, deleting, the recent-notes cache,
the backend pipeline, database upkeep and backups, crash recovery, logging and the
menu-bar hint. Update it in
the same commit as any change to one of those flows.

## Next plans
See [plan_to_implement.md](plan_to_implement.md) for what's done and what's next,
and [CHANGELOG.md](CHANGELOG.md) for what changed when.
