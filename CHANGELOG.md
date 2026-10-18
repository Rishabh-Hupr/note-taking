# Changelog

## 2026-10-18

### New features
- **Automatic backups.** Every 2 days Butler saves a full copy of your notes to
  `~/.butler/backups/` and keeps the last 7 (about two weeks). Each copy is checked
  before it's kept, and search works in it as-is. [RUNBOOK.md](RUNBOOK.md) shows
  how to restore one.
- **The database tidies itself up** at the same time: the search index is
  compacted, and space left behind by deleted or edited notes is reclaimed once it
  reaches a fifth of the file. If the search index ever falls out of step with your
  notes, it's rebuilt. All of this runs in the background (about 14ms on your
  notes), never during startup, and search keeps working while it runs.

### Docs
- **New [DATA_FLOW.md](DATA_FLOW.md)**: diagrams of how a note moves through Butler
  (hotkey → overlay → backend → database and back), covering search, save, delete,
  the recent-notes cache, crash recovery and logging. They render on GitHub and in
  VS Code.

## 2026-10-17

### New features
- **Logs no longer grow forever.** `app.log` and `butler-ui.log` each roll over at
  1MB, keeping the 3 previous files (`.1`–`.3`), so they stay under ~4MB each.
  `butler-ui.log` also keeps its history across launches now instead of being
  wiped each time. A failed rollover never loses old logs, and deleting a log
  while Butler runs is fine — a fresh one starts within a few seconds.

### Security
- **Your note text is no longer written to the logs** — saves and deletes log the
  key and the length only. Log files are now readable only by you.

### Bug fixes
- **Copy, paste, cut, select-all and undo/redo now work** in the add-note and
  search windows (⌘C ⌘V ⌘X ⌘A ⌘Z ⇧⌘Z). They were ignored because Butler's windows
  don't take over as the active app.
- **The long-note preview no longer covers the search window or runs off the
  screen when a note has a very long title.** The title used to stay on one line
  and stretch the preview wider than planned; it now wraps (up to 3 lines).

### Changes
- **The long-note preview opens on whichever side has more room** (left or
  right of the search window), instead of always preferring the right.
- **Colorful menu-bar icon**: Butler now shows a yellow ledger 📒 instead of a
  grey outline, so it's easy to spot next to other menu-bar apps.
- **"Last note" hint**: every 2 hours the icon briefly shows how long ago you saved
  a note (e.g. `📒 last note 3h ago`) for 20 seconds — a gentle nudge to capture
  something. It never pops up or takes focus. Choose how often (off, 30 minutes,
  1, 2 or 4 hours) from **📒 → Last-Note Reminder**; the choice is remembered.
- **Launch scripts stop any running Butler** from this repo — release or test
  build — and print which PIDs they stopped, so two copies never fight over the
  hotkeys.

## 2026-10-11

### Bug fixes
- **Search no longer slows down (or fails) as your notes grow.** The app was
  re-reading the backend's reply from the start every time another piece of it
  arrived, so opening search took ~0.4s at 10,000 notes and timed out entirely
  past ~35,000. Each byte is now read once.
- **Holding ↑/↓ no longer flickers the long-note preview.** At either end of the
  list nothing happens any more, and the preview now waits until you stop on a
  note (0.1s) and updates once, instead of opening and closing on every row.
- **Typing in search no longer lags.** Search used to run on every keystroke,
  replaying the open-the-top-note animation each time; it now waits until you
  pause typing for 0.1s.

### Changes
- **Search fills from memory**: the app keeps your recent notes in memory and
  fills the list from there right after the window opens, instead of asking the
  backend each time. The list is refreshed after every save and delete, and
  re-checked in the background each time search opens. Clearing the search field
  brings the list back instantly too.
- **The search window is taller**, showing about 4 more notes at once.
- **Animated dots** at the right of the search field show a search is running
  while you type, and disappear when the results arrive.
- **Search shows at most 200 notes at a time**: the 200 most recently changed
  when you open it, or the 200 best matches once you type. Older notes are still
  found by typing a search. Notes changed in the same second now always come back
  in the same order.
- **Latency logging**: every request writes a `⏱` line to `butler-ui.log` with how
  long the round trip, processing and total took, and every ⌘⌥F logs how long
  opening took. Each request in that log now starts with a `-------------`
  separator, like `app.log`.

## 2026-10-10

### New features
- **A big green "Saved" tick** pops up when you save a note, and the add-note
  window now closes after 0.4s (was 0.75s).
- **Deleting a note shows a short confirmation** ("Deleted "key"") at the bottom
  of the search window.
- **Saved notes are trimmed**: spaces, tabs and blank lines at the start or end of
  the key and value are dropped. A value that's only blank space can't be saved.

### Bug fixes
- Reopening the add-note window right after a save no longer gets it closed by
  the previous save.
- A **long selected note no longer ends in "…"** — it now shows in full (or opens
  the side preview if it's over 8 lines). The row height was being measured 32pt
  too wide.
- **Faster test builds**: `test-butler.sh` now builds in debug mode (~2s after an
  edit instead of ~24s), and a build flag that did nothing was removed.

### Changes
- New menu-bar icon (`square.and.pencil`).
- The app's source files are now grouped into feature folders (`App/`,
  `SearchNote/`, `AddNote/`, `Overlay/`, `Backend/`, `System/`).

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
