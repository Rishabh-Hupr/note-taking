# Butler — macOS overlay (frontend)

Native AppKit overlay for the Butler note store. Resident agent (no Dock icon)
with two hotkeys:
- **⌘⌥F** — search: type to filter notes, ↑/↓ to move, **Enter** to copy the
  selected note to the clipboard, **⌘D** to delete it, **Esc**/click-away to
  dismiss. Notes over 8 lines open in a side preview.
- **⌘⌥P** — put: enter a Key and Value, **⌘Return** to save (**Enter** adds a
  newline), **Esc** to cancel.

Data/search is handled by the Go `butler-core` sidecar over a newline-JSON stdio
protocol. (Space + one modifier is reserved by macOS — Spotlight, input sources,
Finder search — so F/P are used instead.)

## Layout
`Sources/Butler/`, grouped by feature (SwiftPM compiles all subfolders as one module):
- `App/` — `main.swift` (entry point, `.accessory` agent policy) and `AppDelegate.swift`
  (launches the backend, registers hotkeys, owns the panels and menu-bar item).
- `SearchNote/` — `SearchViewController` (search field, results, ↑/↓, ⏎ copy, ⌘D
  delete) and `NotePreviewPanel` (side preview for long notes).
- `AddNote/` — `PutViewController` (key + multi-line value, save).
- `Overlay/` — `OverlayPanel` (borderless floating `NSPanel`), `ConfirmationBadge`
  ("Saved" tick), `LoadingDots` (search-in-progress indicator), `Layout` (pure
  sizing/placement rules, unit-tested).
- `Backend/` — `SidecarClient` (runs `butler-core`, JSON over stdio, watchdog,
  per-request latency logging), `LineFramer` (splits the reply stream into lines,
  each byte scanned once) and `Models` (`Note` / request / response, mirroring the
  Go wire contract).
- `System/` — `GlobalHotKey` (Carbon, no Accessibility permission), `Logging` +
  `RotatingLogFile` (size-rotated `butler-ui.log`) and `EditingShortcuts` (the one table
  behind the Edit menu and the panels' ⌘C/⌘V/⌘Z handling).

## Easiest: from the repo root
```bash
./launch-butler.sh
```
Builds both artifacts into `build/` and launches the app.

## Run (dev, from source)
```bash
cd macos-app
BUTLER_CORE_BIN="$(cd ../go-rewrite && pwd)/butler-core" swift run
```
`BUTLER_CORE_BIN` tells the app where the sidecar binary is. Resolution order:
that env var → a bundled copy (packaged `.app`) → a `butler-core` sibling next to
the app binary (the `build/` layout) → `../go-rewrite/butler-core` (dev fallback).

Then press **⌘⌥F** (search) or **⌘⌥P** (add note). Notes live in `~/.butler/`
(override with `BUTLER_DATA_DIR`).

## Testing
```bash
cd macos-app && swift test
```
Uses **Swift Testing** (XCTest isn't available with Command Line Tools alone).
Tests cover the Go↔Swift JSON wire contract (`ModelsTests`) and the pure overlay
layout rules in `Layout.swift` — text sizing, the 8-line inline / 50-line preview
caps, preview placement, and remembered panel positions (`LayoutTests`).

## Status
- ✅ Summon/dismiss, vibrancy panel, live search, ↑/↓ nav, Enter→copy, ⌘D delete
  (with confirmation).
- ✅ Long-note side preview (`NotePreviewPanel`), deterministic sizing.
- ✅ Put (add-note) overlay: Key + multi-line Value, ⌘Return saves, "Saved" tick.
- ✅ Overlays remember their dragged position.
- ⏳ Packaging into a signed `.app` with `LSUIElement` (Info.plist under `Resources/`).
- ⏳ User-visible "engine unavailable" state on repeated sidecar failure.
