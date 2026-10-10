# Changelog

## 2026-10-10

### Bug fixes
- A **long selected note no longer ends in "…"** — it now shows in full (or opens
  the side preview if it's over 8 lines). The row height was being measured 32pt
  too wide.
- **Faster test builds**: `test-butler.sh` now builds in debug mode (~2s after an
  edit instead of ~24s), and a build flag that did nothing was removed.

### Changes
- New menu-bar icon (`square.and.pencil`).

## 2026-10-09

### New features
- **Long notes open in a side preview**: notes over 8 lines show their full text
  in a panel beside the search bar (up to 50 lines, then it scrolls). The keyboard
  keeps working in the search bar while it's open.
- **The search and add-note windows remember where you dragged them** and reopen
  there, even after a restart.

### Bug fixes
- The selected note's **title no longer disappears** on very long notes.
- The preview is always the **same size for the same note**, and its scrollbar no
  longer covers the text.
- The preview no longer **covers the search window** on narrower screens — it
  narrows to fit instead.
- If the backend fails to restart (e.g. mid-rebuild), the app now **keeps retrying**
  instead of staying broken until you restart it.
- A rare backend error reply is now shown properly instead of hanging for 5 seconds.

### Under the hood
- First **automated tests for the macOS app** (`cd macos-app && swift test`).

## 2026-09-27

### New features
- Delete the selected note with **⌘D** in the search bar.
- The selected note **pops open to show its full text** when it's longer than
  one line; arrow keys still move between notes while it's expanded.
- In the add-note box, **Return now adds a new line and ⌘Return saves** (swapped).
- A **shortcut hint row** in the search bar shows the available actions
  (navigate · copy · delete · close).
- **Faster development rebuilds**: rebuild just the backend and hot-swap it into
  the running app without restarting (`test-butler.sh --go`).
- Logging is more useful: the app records what it sends and receives (with
  timestamps), and deletes now note which note was removed.

### Bug fixes
- The backend no longer crashes while saving a note — this had caused a save to
  show as failed and then get saved twice.
- A long selected note is no longer cut off at the bottom.
- Backend logs no longer mix into the UI log; each has its own file.
