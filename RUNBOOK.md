# Butler — Runbook

## Backups

The backend backs up `~/.butler/notes.db` every 2 days into
`~/.butler/backups/notes-YYYYMMDD-HHMMSS.db` and keeps the newest 7, about two
weeks of history. Each backup is a complete, standalone copy: the notes, the
search index and its triggers. Each one passes SQLite's and FTS5's integrity checks
before it gets its name. It happens 30s after launch if one is due (checked hourly
after that), alongside the upkeep: FTS5 `optimize`, plus `VACUUM` when 20% or more
of the file is free pages. Each run is logged in `app.log` as `maintenance: …`.

To see what's in a backup without touching anything:

```bash
ls -lh ~/.butler/backups/
sqlite3 -readonly ~/.butler/backups/notes-20261018-093000.db "select key, updated_at from notes order by updated_at desc"
```

## Restore a backup

A restore replaces all your notes with the backup's. Notes saved after the
backup are not in it, but step 2 keeps them in `notes.db.old`.

1. **Quit Butler** from the 📒 menu (Quit Butler). Check that nothing still has the
   database open; this should print nothing:
   ```bash
   pgrep -fl butler-core
   ```
2. **Set the current database aside, with its side files**, so you can go back:
   ```bash
   cd ~/.butler
   mv notes.db notes.db.old
   [ -f notes.db-wal ] && mv notes.db-wal notes.db.old-wal
   [ -f notes.db-shm ] && mv notes.db-shm notes.db.old-shm
   ```
   The `-wal` file can hold the most recent saves and belongs to the old
   database. Left next to the restored file, SQLite would replay it onto the
   backup and could corrupt it.
3. **Copy the backup in.** Copy it rather than moving it, so the backup stays intact:
   ```bash
   cp backups/notes-20261018-093000.db notes.db
   chmod 600 notes.db
   ```
4. **Start Butler** (`./launch-butler.sh` from the repo) and search for a note you
   expect to be there. Search works straight away; the index is part of the
   backup.

**To undo a restore,** quit Butler again, then move `notes.db.old` and its
`notes.db.old-wal` / `notes.db.old-shm` back to `notes.db`, `notes.db-wal`,
`notes.db-shm`.

**If search ever misbehaves after a restore**, with Butler quit:
```bash
sqlite3 ~/.butler/notes.db "INSERT INTO notes_fts(notes_fts) VALUES('rebuild')"
```
This regenerates the search index from the notes; it takes milliseconds at
Butler's size.
