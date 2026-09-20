package dao

import (
	"Go-Butler/utils"
	"database/sql"
	"fmt"
)

// PutNote upserts a note keyed on its unique key.
func PutNote(db *sql.DB, key string, value string) error {
	utils.LogIt("-------------")
	utils.LogIt(fmt.Sprintf("Received key: %s; value: %s", key, value))

	_, err := db.Exec(`
		INSERT OR REPLACE INTO notes(key, value, created_at)
		VALUES ($1, $2, CURRENT_TIMESTAMP)
	`, key, value)
	if err != nil {
		utils.Error_happened(err)
		return err
	}

	utils.LogIt(fmt.Sprintf("%s : %s Saved", key, value))
	return nil
}
