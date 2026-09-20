package dao

import (
	"Go-Butler/utils"
	"database/sql"
	"fmt"
	"strings"
)

// ShowDB returns every note, newest first.
func ShowDB(db *sql.DB) ([]Note, error) {
	utils.LogIt("-------------")
	utils.LogIt("Printing database...")

	rows, err := db.Query(`
		SELECT key, value, created_at, updated_at FROM notes
		ORDER BY updated_at DESC
	`)
	if err != nil {
		utils.Error_happened(err)
		return nil, err
	}
	defer rows.Close()

	var notes []Note
	for rows.Next() {
		var n Note
		if err := rows.Scan(&n.Key, &n.Value, &n.CreatedAt, &n.UpdatedAt); err != nil {
			utils.Error_happened(err)
			return nil, err
		}
		notes = append(notes, n)
	}
	return notes, rows.Err()
}

// FetchNote runs a full-text prefix search over both key and value, ranked by
// FTS relevance (best first). An empty query lists everything (like ShowDB).
// If the FTS search errors on odd input, it falls back to a LIKE scan.
func FetchNote(db *sql.DB, query string) ([]Note, error) {
	utils.LogIt("-------------")
	utils.LogIt(fmt.Sprintf("Received query: %s, searching db...", query))

	// Empty query means "everything" — a phrase-prefix of an empty string would
	// otherwise match nothing rather than listing all notes.
	if strings.TrimSpace(query) == "" {
		return ShowDB(db)
	}

	notes, err := ftsSearch(db, query)
	if err != nil {
		// FTS parse/eval errors surface during row iteration (rows.Err), not at
		// db.Query time, so ftsSearch reports them and we fall back here.
		utils.LogIt(fmt.Sprintf("FTS search failed (%v), falling back to LIKE", err))
		return fetchLike(db, query)
	}

	utils.LogIt(fmt.Sprintf("Fetched %d results", len(notes)))
	return notes, nil
}

// ftsSearch is the FTS5 path. It returns an error from any stage — including
// row iteration, where FTS MATCH evaluation errors actually surface.
func ftsSearch(db *sql.DB, query string) ([]Note, error) {
	// Wrap the raw input as a quoted phrase-prefix so special characters
	// (":", "-", quotes, spaces) can't produce an FTS5 syntax error.
	match := fmt.Sprintf(`"%s"*`, strings.ReplaceAll(query, `"`, `""`))

	rows, err := db.Query(`
		SELECT notes.key, notes.value, notes.created_at, notes.updated_at, notes_fts.rank
		FROM notes
		JOIN notes_fts ON notes.id = notes_fts.rowid
		WHERE notes_fts MATCH ?
		ORDER BY notes_fts.rank
	`, match)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var notes []Note
	for rows.Next() {
		var n Note
		if err := rows.Scan(&n.Key, &n.Value, &n.CreatedAt, &n.UpdatedAt, &n.Rank); err != nil {
			return nil, err
		}
		notes = append(notes, n)
	}
	return notes, rows.Err()
}

// fetchLike is the fallback path: a plain substring search over key and value.
// LIKE wildcards in the query are escaped so % and _ match literally.
func fetchLike(db *sql.DB, query string) ([]Note, error) {
	esc := strings.NewReplacer(`\`, `\\`, `%`, `\%`, `_`, `\_`).Replace(query)
	like := "%" + esc + "%"
	rows, err := db.Query(`
		SELECT key, value, created_at, updated_at FROM notes
		WHERE key LIKE ? ESCAPE '\' OR value LIKE ? ESCAPE '\'
		ORDER BY updated_at DESC
	`, like, like)
	if err != nil {
		utils.Error_happened(err)
		return nil, err
	}
	defer rows.Close()

	var notes []Note
	for rows.Next() {
		var n Note
		if err := rows.Scan(&n.Key, &n.Value, &n.CreatedAt, &n.UpdatedAt); err != nil {
			utils.Error_happened(err)
			return nil, err
		}
		notes = append(notes, n)
	}
	return notes, rows.Err()
}
