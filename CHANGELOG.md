# Changelog

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
