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
		SELECT key, value, created_at FROM notes
		ORDER BY created_at DESC
	`)
	if err != nil {
		utils.Error_happened(err)
		return nil, err
	}
	defer rows.Close()

	var notes []Note
	for rows.Next() {
		var n Note
		if err := rows.Scan(&n.Key, &n.Value, &n.CreatedAt); err != nil {
			utils.Error_happened(err)
			return nil, err
		}
		notes = append(notes, n)
	}
	return notes, rows.Err()
}

// FetchNote runs a full-text prefix search over both key and value, ranked by
// FTS relevance (best first). Falls back to a LIKE scan if the FTS MATCH query
// errors on partial/odd input.
func FetchNote(db *sql.DB, query string) ([]Note, error) {
	utils.LogIt("-------------")
	utils.LogIt(fmt.Sprintf("Received query: %s, searching db...", query))

	// Wrap the raw input as a quoted phrase-prefix so special characters
	// (":", "-", quotes, spaces) can't produce an FTS5 syntax error.
	match := fmt.Sprintf(`"%s"*`, strings.ReplaceAll(query, `"`, `""`))

	rows, err := db.Query(`
		SELECT notes.key, notes.value, notes.created_at, notes_fts.rank
		FROM notes
		JOIN notes_fts ON notes.id = notes_fts.rowid
		WHERE notes_fts MATCH ?
		ORDER BY notes_fts.rank
	`, match)
	if err != nil {
		utils.LogIt(fmt.Sprintf("FTS match failed (%v), falling back to LIKE", err))
		return fetchLike(db, query)
	}
	defer rows.Close()

	var notes []Note
	for rows.Next() {
		var n Note
		if err := rows.Scan(&n.Key, &n.Value, &n.CreatedAt, &n.Rank); err != nil {
			utils.Error_happened(err)
			return nil, err
		}
		notes = append(notes, n)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}

	utils.LogIt(fmt.Sprintf("Fetched %d results", len(notes)))
	return notes, nil
}

// fetchLike is the fallback path: a plain substring search over key and value.
func fetchLike(db *sql.DB, query string) ([]Note, error) {
	like := "%" + query + "%"
	rows, err := db.Query(`
		SELECT key, value, created_at FROM notes
		WHERE key LIKE ? OR value LIKE ?
		ORDER BY created_at DESC
	`, like, like)
	if err != nil {
		utils.Error_happened(err)
		return nil, err
	}
	defer rows.Close()

	var notes []Note
	for rows.Next() {
		var n Note
		if err := rows.Scan(&n.Key, &n.Value, &n.CreatedAt); err != nil {
			utils.Error_happened(err)
			return nil, err
		}
		notes = append(notes, n)
	}
	return notes, rows.Err()
}
