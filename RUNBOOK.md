# Butler — Runbook

## Backups

This section is the one place the schedule is written down. The values are the
constants at the top of
[go-rewrite/maintenance.go](go-rewrite/maintenance.go); update this section if
you change them.

| What | Value | Constant |
|---|---|---|
| Backup when the newest is at least | 2 days old | `backupInterval` |
| Backups kept | newest 7 (about two weeks) | `backupsToKeep` |
| First check after the backend starts | 30s | `firstCheckDelay` |
| Then checked every | hour | `checkEvery` |
| After a failed pass, next try | 6 hours later | `retryAfterFailure` |
| `VACUUM` when free pages are at least | 20% of the file | `vacuumFreeRatio` |

Backups land in `~/.butler/backups/notes-YYYYMMDD-HHMMSS.db`, with the time in
**UTC**. Each is a complete, standalone copy: the notes, the search index and its
triggers. A copy must pass SQLite's `quick_check` before it gets its name. If only
its search index was out of sync with the notes, the index is rebuilt in the copy
and in the live database too.

The backup runs first. Then the live database is tidied: FTS5 `optimize`, then
`VACUUM` if fragmented. All of it runs in the background. Searches carry on
during it; a save only waits while a write step runs. In a 100k-note test the
pass took 1.4s, and saves waited at most 42ms. Each pass is logged in `app.log` as `maintenance: …`.

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

**To undo a restore,** quit Butler again (step 1), then:
```bash
cd ~/.butler
rm -f notes.db notes.db-wal notes.db-shm   # the restored copy and its side files
mv notes.db.old notes.db
[ -f notes.db.old-wal ] && mv notes.db.old-wal notes.db-wal
[ -f notes.db.old-shm ] && mv notes.db.old-shm notes.db-shm
```
The restored copy's `-wal` has to go first. Otherwise SQLite would replay it onto
the old database. This throws away anything saved since the restore; to keep it,
move those three files aside instead of deleting them.

**If search ever misbehaves after a restore**, with Butler quit:
```bash
sqlite3 ~/.butler/notes.db "INSERT INTO notes_fts(notes_fts) VALUES('rebuild')"
```
This regenerates the search index from the notes; it takes milliseconds at
Butler's size.
