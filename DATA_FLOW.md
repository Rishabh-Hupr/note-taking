# Butler — Data & Code Flow

How data moves through Butler, and which code handles each step. The diagrams are
[Mermaid](https://mermaid.js.org/) and render on GitHub and in VS Code's Markdown
preview.

> **Keep this file current.** Any change to a flow below (a new command, a new
> cache, a changed timing, a new log) updates the matching diagram in the same
> commit. Numbers in diagrams (debounce, timeouts, caps) must match the code.

## 1. Components

```mermaid
flowchart LR
    user([You])

    subgraph app["macOS app — macos-app/ (Swift, AppKit)"]
        hotkeys["GlobalHotKey<br/>⌘⌥F · ⌘⌥P"]
        menu["📒 menu-bar item<br/>AppDelegate"]
        search["SearchViewController<br/>+ NotePreviewPanel"]
        put["PutViewController"]
        cache[("recentNotes<br/>(in memory, ≤200)")]
        client["SidecarClient<br/>+ LineFramer"]
        uilog[["RotatingLogFile<br/>butler-ui.log"]]
    end

    subgraph backend["Backend — go-rewrite/ (Go, butler-core)"]
        loop["main.go<br/>stdin loop · serveLine"]
        proc["processor<br/>SafeHandler → handler"]
        ops["dao/operations<br/>Put · Fetch · ShowDB · Delete"]
        golog[["helpers.LogIt<br/>app.log"]]
    end

    db[("~/.butler/notes.db<br/>SQLite + FTS5")]
    backups[("~/.butler/backups/<br/>newest backupsToKeep")]

    user --> hotkeys
    user --> menu
    hotkeys --> search & put
    menu --> search & put
    search <--> cache
    search --> client
    put --> client
    client -- "JSON line on stdin" --> loop
    loop -- "JSON line on stdout" --> client
    loop --> proc --> ops --> db
    maint["maintainer goroutine<br/>(maintenance.go)"] -- "backup + upkeep when due" --> db
    db -.->|VACUUM INTO| backups
    client -.-> uilog
    search -.-> uilog
    ops -.-> golog
    proc -.-> golog
```

The app starts `butler-core` once at launch and keeps it running. They talk over
the backend's **stdin/stdout pipes**, one JSON object per line. The backend owns
the database and `app.log`; the app owns the UI, the in-memory recent-notes list
and `butler-ui.log`.

## 2. Wire protocol

One request per line from the app, one response per line back, matched by `id`.

| `cmd` | Request fields | Response | Backend function |
|---|---|---|---|
| `ping` | — | `ok` | — |
| `put` | `key`, `value` (both trimmed; must be non-empty) | `ok` | `operations.PutNote` (upsert by key) |
| `fetch` | `query` (`""` = most recent) | `ok`, `notes[]` (≤ 200) | `operations.FetchNote` → FTS5, LIKE fallback |
| `list` | — | `ok`, `notes[]` (≤ 200) | `operations.ShowDB` |
| `delete` | `note_id` | `ok` | `operations.DeleteNote` |

Every response is `{"id": …, "ok": true|false, "notes"?: […], "error"?: "…"}`.
A `Note` is `{id, key, value, created_at, updated_at, rank}`. The Swift
`Models.swift` mirrors the Go `dao.Note`, and `ModelsTests` pins the contract.

## 3. Opening search (⌘⌥F)

```mermaid
sequenceDiagram
    autonumber
    actor You
    participant AD as AppDelegate
    participant SV as SearchViewController
    participant C as recentNotes (memory)
    participant SC as SidecarClient
    participant BE as butler-core

    You->>AD: ⌘⌥F
    AD->>AD: position panel (remembered spot, else default on the mouse's screen)
    AD->>SV: makeKeyAndOrderFront, prepareForShow()
    SV->>SV: clear list → window appears immediately (empty frame is cheap)
    alt cache loaded
        SV-->>SV: next run-loop turn: fill list from cache, select row 0
        SV->>SC: revalidate: fetch("")
        SC->>BE: {"cmd":"fetch","query":""}
        BE-->>SC: ≤200 most recent notes
        SC-->>SV: notes
        alt differs from cache
            SV->>C: update
            SV->>SV: redraw (keep selection)
        else identical
            SV->>SV: nothing (no redraw)
        end
    else cache not loaded yet
        SV->>SC: fetch("")
        SC-->>SV: notes → fill list, store in cache
    end
    SV->>SV: short note (≤8 lines): row expands · long: row stays one line, preview after 0.1s settle
    AD->>AD: log "⏱ open show= prepare= firstFrame= total="
```

Filling the list must stay **after** the window appears. Doing it before the
first frame delayed every open by about 200ms.

## 4. Typing a query

```mermaid
sequenceDiagram
    autonumber
    actor You
    participant SV as SearchViewController
    participant SC as SidecarClient
    participant LF as LineFramer
    participant BE as butler-core
    participant DB as SQLite FTS5

    You->>SV: keystroke
    alt field now empty
        SV->>SV: show recentNotes at once (no debounce, no request), revalidate
    else text
        SV->>SV: start LoadingDots, restart 100ms debounce
        Note over SV: further keystrokes keep restarting the debounce
        SV->>SC: fetch(query)  (after 100ms quiet)
        SC->>SC: record dispatch time, start 5s timeout
        SC->>BE: {"id":n,"cmd":"fetch","query":"…"}
        BE->>DB: MATCH '"query"*' ORDER BY rank, id DESC LIMIT 200
        DB-->>BE: rows (LIKE fallback if MATCH errors)
        BE-->>SC: one JSON line (may arrive in several pipe reads)
        SC->>LF: append(piece) — each byte scanned once
        LF-->>SC: complete line
        SC->>SC: decode, log "⏱ … roundtrip= processing= total="
        SC-->>SV: notes
        SV->>SV: stop dots, reload list, select row 0, schedule preview
    end
```

## 5. Saving a note (⌘⌥P)

```mermaid
sequenceDiagram
    autonumber
    actor You
    participant PV as PutViewController
    participant SC as SidecarClient
    participant BE as butler-core
    participant DB as SQLite
    participant SV as SearchViewController

    You->>PV: key + value, ⌘Return
    PV->>PV: empty / whitespace-only? → "Both key and value are required"
    PV->>SC: put(key, value)
    SC->>BE: {"cmd":"put","key":…,"value":…}
    BE->>BE: TrimSpace(key), TrimSpace(value), reject if empty
    BE->>DB: INSERT … ON CONFLICT(key) DO UPDATE (created_at kept, updated_at bumped)
    DB->>DB: triggers keep notes_fts in sync
    BE-->>SC: ok
    SC-->>PV: ok
    PV->>SV: onSaved → refreshRecent() (background fetch(""))
    PV->>PV: clear draft, show "✓ Saved" 400ms, close
```

## 6. Deleting a note (⌘D in search)

```mermaid
sequenceDiagram
    autonumber
    actor You
    participant SV as SearchViewController
    participant SC as SidecarClient
    participant BE as butler-core

    You->>SV: ⌘D on selected note
    SV->>SC: delete(id)
    SC->>BE: {"cmd":"delete","note_id":id}
    BE-->>SC: ok (FTS cleaned by trigger)
    SV->>SV: re-run current search, keep cursor near the deleted row
    SV->>SV: refreshRecent()
    SV->>SV: hint row shows "🗑 Deleted "key"" for 1.5s
```

## 7. Recent-notes cache lifecycle

```mermaid
flowchart TD
    launch([App launch]) -->|refreshRecent| fill[fetch empty query]
    save([Save succeeds]) -->|onSaved → refreshRecent| fill
    del([Delete succeeds]) -->|refreshRecent| fill
    typed([Search with empty query]) -->|result stored| cache
    fill --> cache[("recentNotes")]
    open([⌘⌥F]) -->|fill list next run-loop turn| cache
    open -->|revalidate in background| fill2[fetch empty query]
    fill2 -->|only if different| cache
    cleared([Field cleared]) -->|show directly, then revalidate| cache
    cache -->|newestNote| hint["📒 last note … hint"]
```

The cache is never "invalidated". It's refreshed at every point where notes can
change, and the revalidation on open catches anything else, such as a backend
hot-swap.

## 8. Backend request pipeline

```mermaid
flowchart TD
    stdin[/"stdin line"/] --> serve["main.serveLine<br/>(recovers panics per line)"]
    serve -->|bad JSON| bad["error response, id recovered by bestEffortID"]
    serve --> safe["processor.SafeHandler<br/>(recovers panics per request)"]
    safe --> h{"handler: cmd"}
    h -->|put| put["trim → PutNote (upsert)"]
    h -->|fetch| fetch{"query empty?"}
    fetch -->|yes| show["ShowDB: ORDER BY updated_at DESC, id DESC LIMIT 200"]
    fetch -->|no| fts["ftsSearch: MATCH phrase-prefix, ORDER BY rank LIMIT 200"]
    fts -->|error| like["fetchLike: escaped LIKE, LIMIT 200"]
    h -->|list| show
    h -->|delete| delete["DeleteNote by id"]
    h -->|ping| ok["ok"]
    put & show & fts & like & delete & ok & bad --> write["processor.WriteResponse<br/>(fallback line if JSON encoding fails)"]
    write --> stdout[/"stdout line"/]
```

## 9. Database upkeep and backups

Runs on its own goroutine (`maintainer.run`), next to the request loop. The
schedule constants are listed in [RUNBOOK.md](RUNBOOK.md#backups); they're
referred to here by name.

```mermaid
flowchart TD
    tick(["firstCheckDelay after start, then every checkEvery"]) --> due{"due?<br/>newest backup not dated in the future<br/>is ≥ backupInterval old (or none),<br/>and no failure in the last retryAfterFailure"}
    due -->|no| idle(["nothing (one directory read)"])
    due -->|yes| prep["backups/ → 0700, remove leftover .partial files"]
    prep --> bk["VACUUM INTO notes-YYYYMMDD-HHMMSS.db.partial (UTC)"]
    bk --> qc{"quick_check ok?"}
    qc -->|no| fail["delete .partial, log, back off retryAfterFailure<br/>(existing backups untouched)"]
    qc -->|yes| fts{"copy's FTS index in sync?"}
    fts -->|no| fix["rebuild index in the copy, re-check"]
    fix -->|still broken| fail
    fix -->|ok| keep
    fts -->|yes| keep["chmod 600, rename to final name"]
    keep --> prune["prune to backupsToKeep<br/>(future-dated ones go first)"]
    prune --> live{"index drifted?"}
    live -->|yes| rebuild["live FTS rebuild"]
    live -->|no| opt["live FTS optimize"]
    rebuild & opt --> frag{"free pages ≥ vacuumFreeRatio?"}
    frag -->|yes| vac["VACUUM, then wal_checkpoint(TRUNCATE)"]
    frag -->|no| log
    vac --> log["app.log: maintenance: … done in Nms"]
```

```mermaid
sequenceDiagram
    participant R as request loop (searches, saves)
    participant DB as notes.db (WAL)
    participant M as maintainer goroutine

    M->>DB: VACUUM INTO copy (read snapshot)
    R->>DB: searches and saves carry on (WAL readers/writers unaffected)
    M->>DB: FTS optimize / VACUUM (write lock)
    R->>DB: a save waits (busy timeout 5s), searches carry on
    Note over R,M: measured at 100k notes: pass 1.4s, searches max 117ms, saves max 42ms
```

Restoring is manual; see [RUNBOOK.md](RUNBOOK.md).

## 10. Resilience

```mermaid
flowchart LR
    exit(["butler-core exits / crashes"]) --> term["SidecarClient.handleTermination"]
    term --> failall["fail in-flight requests (notRunning)"]
    term --> reset["detach old pipe, reset LineFramer, bump generation"]
    term --> retry["startWithRetry: backoff 0.1s → 5s, keeps retrying"]
    req(["any request"]) --> timeout["5s timeout → SidecarError.timeout"]
    stale(["bytes from a dead process"]) --> drop["ignored (generation mismatch)"]
```

## 11. Logging

```mermaid
flowchart LR
    subgraph app["App"]
        uilog["uiLog()"] --> rlf["RotatingLogFile"]
        nslog["NSLog / crashes / print"] --> fd12["stderr + stdout"]
        rlf --> fd12
    end
    fd12 --> uifile[("butler-ui.log")]

    subgraph be["Backend"]
        logit["helpers.LogIt()"] --> gofile[("app.log")]
        panics["Go panics (stderr)"] -->|BUTLER_STDERR_TO_LOG=1| gofile
    end
```

Both logs:
- **Rotate at 1MB, keeping 3 backups.** Rotation moves the full log aside and opens the fresh file before shifting backups, so a failed rotation loses nothing and retries after 60s.
- **Stay open, with the size tracked by a counter**, so there's no stat call per line.
- **Re-check every 5s** that the file is still there, and reopen it if it was deleted by hand.
- **Are private** (`0600`).

**Note text is never logged:** saves and deletes log only the key and the length.

## 12. "Last note" hint

```mermaid
sequenceDiagram
    participant AD as AppDelegate
    participant LS as LastSavedHint
    participant SV as SearchViewController
    participant MB as 📒 menu-bar item

    loop every interval (menu choice, default 2h, BUTLER_HINT_INTERVAL overrides)
        AD->>SV: newestNote (cache) — or one fetch("") if not loaded
        alt backend unavailable
            AD->>AD: skip this hint
        else
            AD->>LS: text(newestUpdatedAt)
            AD->>MB: "📒 last note 3h ago" for 20s, then "📒"
        end
    end
```
