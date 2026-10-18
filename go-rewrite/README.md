## Execution
1. `cd go-rewrite`
2. `CGO_ENABLED=1 go run -tags "sqlite_fts5" .`

## Testing
Run from `go-rewrite/`. The `sqlite_fts5` build tag is required (FTS5 + cgo):

```bash
CGO_ENABLED=1 go test -tags sqlite_fts5 ./...
```

Tests live with the code they cover: `dao/operations` (put/fetch/show/like),
`processor` (request handler + response), and the root `main` package
(`dataDir`, `bestEffortID`, the request loop, and database maintenance in
`maintenance.go`: backups, pruning, VACUUM, FTS optimize).

## Maintenance
`maintenance.go` runs backups and upkeep on a background goroutine, started from
`main`. The constants at the top of the file set the schedule; the values are
listed in [RUNBOOK.md](../RUNBOOK.md#backups). A pass:
1. Writes a backup first: `VACUUM INTO` a `.partial` file, which must pass
   `quick_check`. If only its search index is out of sync, the index is rebuilt.
   Then it's renamed into place and old backups are pruned.
2. Tidies the live DB: FTS5 `rebuild` if the copy showed drift, otherwise
   `optimize`; then `VACUUM` (plus a WAL truncate) when fragmented.

Searches aren't blocked (WAL). Saves wait on a write step through go-sqlite3's
default 5s busy timeout. `TestRunIfDue_ConcurrentRequestsSucceed` covers this.
Restoring is manual; see [RUNBOOK.md](../RUNBOOK.md).
