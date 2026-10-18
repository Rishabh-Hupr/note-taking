# Butler — Implementation Plan & Log

Butler is a Spotlight-style macOS note utility: a **native Swift/AppKit overlay**
(`macos-app/`) summoned by a global hotkey, backed by a **resident Go SQLite/FTS5
sidecar** (`go-rewrite/`, binary `butler-core`) that they talk to over a
newline-delimited JSON protocol on stdin/stdout. Notes live in `~/.butler/`.
Hotkeys today: **⌘⌥F** search, **⌘⌥P** add.

> History: this app went Python CLI → Go port → Zenity dialogs → a failed
> Wails/React attempt → a considered BubbleTea CLI → the current native overlay.
> Earlier approaches are preserved on the `python`, `failedWailsApproach`, and
> `zenity` branches. The original pivot notes live in `go-rewrite/plan_to_implement.md`.

---

## ✅ Done

### Phase 1 — Go stdio sidecar
- Rewrote `main.go` from a one-shot Zenity CLI into a long-running newline-JSON
  service (`ping` / `put` / `fetch` / `list`), dispatched via a `switch` so new
  ops are cheap to add. Exits on stdin EOF.
- Shared `dao.Note{key,value,created_at,updated_at,rank}` model = the wire contract.
- FTS5 search over **key and value**, ranked; quoted-phrase-prefix so odd input
  can't break the query; LIKE fallback; empty query lists all.
- Truthful timestamps via `INSERT … ON CONFLICT DO UPDATE` (created_at preserved,
  updated_at bumped).
- `~/.butler` data dir (env `BUTLER_DATA_DIR`); dropped zenity/clipboard deps.
- `safeHandle` recovers per-request panics so one bad request can't kill the sidecar.
- Unit tests (`go test -tags sqlite_fts5 ./...`).

### Phase 2 — Resident agent + overlay panel
- `.accessory` agent (no Dock icon). Borderless, floating, all-Spaces `NSPanel`
  with `NSVisualEffectView` blur; `canBecomeKey` so typing works.
- Global hotkey via Carbon `RegisterEventHotKey` (no Accessibility permission);
  one shared event handler.

### Phase 3 — Wire the sidecar
- `SidecarClient` launches `butler-core`, matches requests↔responses by id,
  per-request timeout, safe writes, and a relaunch watchdog with backoff.

### Phase 4 — Search + Put
- Search: live fetch, ↑/↓ nav, **Enter** copies to `NSPasteboard`, Esc/click-away.
- Put overlay: Key + multi-line Value (placeholder, **Return newline, ⌘Return save**,
  Shift+Tab back to key), drafts preserved on dismiss, green "✓ Saved" confirmation.

### Phase 5 — Delete + note-view polish
- **Delete the selected note with ⌘D** in search. Chosen over ⌘⌫ (which would
  clobber the search field's text). Backend `delete` cmd + `DeleteNote(db, id)`
  keyed on the note **`id`** (stable primary key — `id` is now on the wire and in
  every SELECT/scan), plus `SidecarClient.delete(id:)`. Deletes immediately and
  refreshes the list (no confirm). Unit tests incl. FTS-index sync + no-op delete.
- **Full-content pop-out:** the selected note's row expands with a quick fade to
  show its whole multi-line value; ↑/↓ navigation still works while expanded.
- **Shortcut hint row** in the search overlay (↑↓ navigate · ⏎ copy · ⌘D delete · ⎋ close).
- Notes: deviated from the original plan — delete by **id not key**, shortcut
  **⌘D not ⌘⌫**, and no confirm/undo (fast launcher-style UX).

### Phase 6 — Long notes, remembered positions, frontend tests
- **Side preview for long notes:** notes over 8 wrapped lines open `NotePreviewPanel`
  beside the overlay (fade + slide in) with the full text, up to 50 lines then
  scrolling. Never takes key, so ↑/↓, ⏎, ⌘D keep working. Sizing comes only from
  the text and a fixed wrap width (scroller sits in a reserved gutter), so it's
  deterministic. Narrows (min 300pt) rather than covering the overlay.
- Selected row pins the key to the top; results table uses `.plain` style so row
  heights are measured at the width the text actually wraps at (`.inset` padded
  rows 16pt a side and cut long notes off with "…").
- Search and add-note overlays **remember their dragged position** (`UserDefaults`),
  clamped on-screen, falling back to centered if that display is gone.
- Watchdog retries failed sidecar launches; Go's marshal-failure fallback includes
  `"ok":false`.
- **Swift Testing suite** (`cd macos-app && swift test`): wire contract, layout
  rules (`OverlayLayout`), row-height vs real cell layout.
- Dev loop: `test-butler.sh` builds debug (~2s incremental); dropped the no-op
  `-module-cache-path` flag.
- **Feedback:** big green "Saved" `ConfirmationBadge` on put (dialog closes after
  400ms, guarded so a pending dismiss can't close a reopened dialog); ⌘D shows a
  brief "Deleted" message in the search hint row.
- **Trim on save:** the Go `put` handler `TrimSpace`s key and value; whitespace-only
  values are rejected (and the dialog treats them as empty).
- Swift sources grouped into feature folders: `App/`, `SearchNote/`, `AddNote/`,
  `Overlay/`, `Backend/`, `System/`.
- **Scale (measured, 2026-10-11):** empty-query search loaded every note. With
  300-byte notes: 10k → 4MB reply, 100k → 42MB. The bottleneck was Swift's stdout
  framing (rescanned the whole buffer per ~64KB pipe piece: 0.4s at 10k, 34s at
  100k, past the 5s timeout at ~35k), not SQLite (345ms at 100k) or JSON. Fixed:
  - `LineFramer` scans each byte once (21MB: 25.7s → ms; regression test).
  - `operations.MaxResults = 200` caps list and every search path (`LIMIT`), with
    `id DESC` as a tie-breaker so the cap is deterministic.
  - Per-request latency in `butler-ui.log`: `⏱ … roundtrip= processing= total=`
    (dispatch → reply received → decoded).
- **Typing debounce:** search runs 0.1s after the last keystroke instead of per
  character (per-keystroke search replayed the row-grow + preview animations).
  `LoadingDots` (•/••/•••) at the search field's right shows the wait + fetch.
- Search window 640×400 → 640×592 (~4 more 48pt rows visible).
- **Preview settles before updating:** ↑/↓ at the list ends is a no-op (was
  re-selecting the same row ~30×/s); the side preview updates 0.1s after the
  selection stops (`schedulePreview`), so holding an arrow doesn't flicker it.
- **Recent-notes cache:** `SearchViewController.recentNotes` holds the empty-query
  result in memory; ⌘⌥F shows the window first, then fills from it on the next
  run-loop turn (no round trip). Filling *before* the first frame cost ~200ms per
  open (layout of the list), so it must stay after the window appears. Warmed at launch,
  refreshed after put (`PutViewController.onSaved`) and delete, and revalidated in
  the background on each open (only redraws if the backend's list differs).
  Clearing the field shows the cache immediately (no debounce, no round trip).
- Open latency logged per ⌘⌥F: `⏱ open show= prepare= firstFrame= total=`.

### Extras (beyond the original plan)
- Sidecar stderr → `app.log`; timestamped UI request/response logging to `butler-ui.log`.
- Per-request panic recovery (`serveLine`) so a bad request can't crash the sidecar.
- `test-butler.sh --go/--be` rebuilds only the Go sidecar and hot-swaps it into the
  running app (watchdog respawn).
- Edit-menu so ⌘C/⌘V/⌘X/⌘A + ⌘Q work in the overlays.
- Overlay clamped to `visibleFrame` (no off-screen clip).
- Minimal **menu-bar status item** (📒 emoji title — renders in color, unlike a template symbol) with Search / Add Note / Quit.
- **Log rotation:** Go `helpers` logger (app.log) and Swift `RotatingLogFile`
  (butler-ui.log, installed as stderr+stdout via dup2 so NSLog/crashes land in it)
  rotate at 1MB keeping 3 backups; files 0600. Both keep the file open and track its
  size with a counter (no stat/reopen per line); every 5s they check the file at the
  path is still theirs and reopen if it was deleted by hand. Rotation moves the log
  aside and opens the fresh one *before* shifting backups, so a failed rotation loses
  nothing (retried after 60s). Go owns app.log end to end: asked via
  `BUTLER_STDERR_TO_LOG=1` (set by the app), it also points its stderr at the log,
  after every rotation too; run by hand it keeps its own stderr. Launch scripts append (`>>`) instead of
  truncating. Put/delete log key + length, never note text (was review #5).
- **Editing shortcuts:** one table, `EditingShortcuts.all`, builds both the Edit menu
  and `OverlayPanel.performKeyEquivalent`'s dispatch (menu key equivalents never fire
  — the panels are non-activating), so they can't drift. Falls back to the physical
  key on non-Latin layouts; value box `allowsUndo`. Unit-tested.
- **Scripts:** both launch scripts source `scripts/butler-common.sh` (`stop_butler`),
  so the stop logic lives once.
- **Preview side:** `previewHorizontal` picks the side with more room (right on ties).
- **Preview bounds:** a wide key stretched the panel (1193pt vs 420) over the search
  window / off-screen — a single-line label resists compression and widens its
  window. Key now wraps (≤3 lines, `preferredMaxLayoutWidth`, low compression
  resistance) and its height counts toward the panel height; slide-in distance <
  gap. Regression test places it on both sides with a wide key.
- **Last-note hint:** every 2h the item reads `📒 last note 3h ago` for 20s (`LastSavedHint`,
  unit-tested; newest note from the recent-notes cache). Interval chosen in the menu
  (📒 → Last-Note Reminder: Off / 30m / 1h / 2h / 4h), saved in `UserDefaults`
  (`butler.lastNoteHintInterval`, 0 = off), applied immediately.
  `BUTLER_HINT_INTERVAL=<sec>` overrides it for testing.
- `launch-butler.sh` — builds both halves, launches backgrounded, idempotent reruns.
- Accurate root `README.md`; repo history rewritten to the personal GitHub identity.

---

## 🔜 Next steps

### Configurable hotkeys
- Let users rebind the search / put combos instead of hard-coded ⌘⌥F / ⌘⌥P.
- Persist choices in `UserDefaults`; re-register `GlobalHotKey` from the stored
  values on change (unregister the old first).
- UI: a small Preferences window (menu-bar → "Preferences…") with a shortcut
  recorder — either a custom key-capture field or the `KeyboardShortcuts` SPM package.
- Validate against macOS-reserved combos (Spotlight, input sources, Finder search).

### Notch integration (UI drops from the notch)
- Position the overlay at **top-center, docked under the menu bar**, so it looks
  like it emerges from the MacBook notch.
- Use `NSScreen.safeAreaInsets` / `auxiliaryTopLeftArea` to detect the notch and
  align to it; optionally shape/round the panel's top to hug the cutout, and add a
  short "drop from the notch" reveal animation.
- Gracefully fall back to the current upper-third centering on non-notched displays.

### Phase 7 — Packaging (make it a real app)
- Build a signed `Butler.app`: `Info.plist` with `LSUIElement`, bundle `butler-core`
  into `Contents/Resources/` (Xcode Run Script or a package step), resolve it via
  `Bundle.main` at runtime.
- Ad-hoc codesign (`codesign --force --deep --sign -`).
- `SMAppService` login item so it auto-starts and stays resident — double-click
  install, no terminal.

### Observability
- Optional: ship the `⏱` latencies to a local Prometheus (+ Grafana) for real-time
  graphs. Pull model: something must expose `/metrics` on `127.0.0.1` for Prometheus
  to scrape.

### Code-review follow-ups (2026-10-09, open)
- ⌘D does nothing with Caps Lock on (exact modifier-flag match).
- Remove dead `RebuildFTSTable` (duplicates the trigger SQL).
