# Butler — macOS overlay (frontend)

Native AppKit overlay for the Butler note store. Resident agent (no Dock icon)
summoned by **⌘⌥Space**: type to search notes, ↑/↓ to move, **Enter** to copy the
selected note to the clipboard, **Esc** or click-away to dismiss. Data/search is
handled by the Go `butler-core` sidecar over a newline-JSON stdio protocol.

## Layout
- `Sources/Butler/main.swift` — entry point; sets `.accessory` (agent) policy.
- `AppDelegate.swift` — launches the sidecar, registers the hotkey, owns the panel.
- `GlobalHotKey.swift` — Carbon `RegisterEventHotKey` (no Accessibility permission).
- `OverlayPanel.swift` — the borderless, floating, all-Spaces `NSPanel`.
- `SearchViewController.swift` — vibrancy + search field + results table + key handling.
- `SidecarClient.swift` — runs `butler-core`, matches requests↔responses, basic watchdog.
- `Models.swift` — `Note` / request / response, mirroring the Go wire contract.

## Build the sidecar first
```bash
cd ../go-rewrite
CGO_ENABLED=1 GOPROXY=direct GOSUMDB=off go build -tags sqlite_fts5 -o butler-core .
```

## Run (dev)
```bash
cd macos-app
BUTLER_CORE_BIN="$(cd ../go-rewrite && pwd)/butler-core" swift run
```
`BUTLER_CORE_BIN` tells the app where the sidecar binary is. Without it, it looks
for `../go-rewrite/butler-core` relative to the working directory, then a bundled
copy (for a packaged `.app`).

Then press **⌘⌥Space** to summon the overlay. Notes live in `~/.butler/` (override
with `BUTLER_DATA_DIR`).

## Status (MVP)
- ✅ Summon/dismiss, vibrancy panel, live search, ↑/↓ nav, Enter→copy.
- ⏳ Put (add-note) flow — protocol + client method exist (`sidecar.put`), UI TBD.
- ⏳ Packaging into a signed `.app` with `LSUIElement` (Info.plist under `Resources/`).
- ⏳ User-visible "engine unavailable" state on repeated sidecar failure.
