package dao

import (
	"Go-Butler/utils"
	"database/sql"
	"fmt"
)

func PutNote(db *sql.DB, key string, value string) {
	// logging_utils
	utils.LogIt("-------------")
	log := fmt.Sprintf("Received key: %s; value: %s", key, value)
	utils.LogIt(log)

	// querying DB
	_, err := db.Exec(`
		INSERT OR REPLACE into notes(key, value, created_at)
		VALUES ($1, $2, CURRENT_TIMESTAMP)
	`, key, value)

	if utils.Error_happened(err) {
		return
	}

	// logging_utils
	log = fmt.Sprintf("%s : %s Saved", key, value)
	utils.LogIt(log)
}
