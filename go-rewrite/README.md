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
`maintenance.go` runs from the main loop, between requests, so it never races a
write. It first runs 30s after start, then checks hourly; it does the work only
when the newest backup in `<data dir>/backups/` is 2+ days old:
1. FTS5 `optimize`.
2. `VACUUM` if ≥20% of pages are free.
3. `VACUUM INTO` a new backup, checked (`quick_check` + FTS5 `integrity-check`)
   before it's renamed into place, then prune to the newest 7.

Restoring is manual; see [RUNBOOK.md](../RUNBOOK.md).
