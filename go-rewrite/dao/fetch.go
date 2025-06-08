package dao

import (
	"Go-Butler/utils"
	"database/sql"
)

func ShowDB(db *sql.DB) map[string]string {
	result := map[string]string{}

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
		result[key] = value + " " + created_at
	}

	return result
}
