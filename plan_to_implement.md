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
- Put overlay: Key + multi-line Value (placeholder, Return saves, ⌘Return newline,
  Shift+Tab back to key), drafts preserved on dismiss, green "✓ Saved" confirmation.

### Extras (beyond the original plan)
- Edit-menu so ⌘C/⌘V/⌘X/⌘A + ⌘Q work in the overlays.
- Overlay clamped to `visibleFrame` (no off-screen clip).
- Minimal **menu-bar status item** (butler figure) with Search / Add Note / Quit.
- `launch-butler.sh` — builds both halves, launches backgrounded, idempotent reruns.
- Accurate root `README.md`; repo history rewritten to the personal GitHub identity.

---

## 🔜 Next steps

### Delete action on notes
- Backend: add a `delete` cmd + `dao.DeleteNote(db, key) error`
  (`DELETE FROM notes WHERE key = ?`; the AFTER-DELETE trigger keeps FTS in sync).
  Add `SidecarClient.delete(key:)`.
- UI: in the search results, a key on the selected row (e.g. **⌘⌫**) deletes it,
  then refreshes the list. Consider a brief confirm or undo to prevent accidents.
- Protocol is already extensible, so this is a one-case + one-function addition.

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

### Phase 5 — Packaging (make it a real app)
- Build a signed `Butler.app`: `Info.plist` with `LSUIElement`, bundle `butler-core`
  into `Contents/Resources/` (Xcode Run Script or a package step), resolve it via
  `Bundle.main` at runtime.
- Ad-hoc codesign (`codesign --force --deep --sign -`).
- `SMAppService` login item so it auto-starts and stays resident — double-click
  install, no terminal.

### Post-MVP polish
- User-facing "engine unavailable — retrying" state if the sidecar keeps failing.
- Migrate any existing notes from the old `db/` folder into `~/.butler`.
