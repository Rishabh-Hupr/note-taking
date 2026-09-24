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
(`dataDir`, `bestEffortID`).
