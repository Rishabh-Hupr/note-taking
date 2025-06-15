package dao

import (
	"Go-Butler/utils"
	"database/sql"
	"fmt"
)

func ShowDB(db *sql.DB) map[string]string {
	result := map[string]string{}

	// logging_utils
	utils.LogIt("-------------")
	log := "Printing database..."
	utils.LogIt(log)

	rows, err := db.Query(`
		SELECT key, value, created_at FROM notes
	`)
	if utils.Error_happened(err) {
		return nil
	}

	defer rows.Close()

	for rows.Next() {
		var key, value, created_at string
		err := rows.Scan(&key, &value, &created_at)
		if utils.Error_happened(err) {
			return nil
		}
		result[key] = value + " - " + created_at
	}

	// logging_utils
	log = "Dumping database..."
	utils.LogIt(log)

	return result
}

func FetchNote(db *sql.DB, query string) map[string]string {
	result := map[string]string{}
	param_query := fmt.Sprintf("key:%s*", query)

	// logging_utils
	utils.LogIt("-------------")
	log := fmt.Sprintf("Received key: %s, Querying db...", query)
	utils.LogIt(log)

	rows, err := db.Query(`
		SELECT notes.key, notes.value FROM notes 
		JOIN notes_fts ON notes.id = notes_fts.rowid
		WHERE notes_fts MATCH ?
	`, param_query)

	if utils.Error_happened(err) {
		return nil
	}

	defer rows.Close()

	for rows.Next() {
		var key, value string
		err := rows.Scan(&key, &value)
		if utils.Error_happened(err) {
			return nil
		}

		result[key] = value
	}

	// logging_utils
	log = fmt.Sprintf("Fetched results: %s", result)
	utils.LogIt(log)

	return result
}
