package dao

import (
	"Go-Butler/utils"
	"database/sql"
	"fmt"
)

// PutNote upserts a note keyed on its unique key. created_at is set by the
// DB, and rank is search-only, so only Key and Value are read from n.
func PutNote(db *sql.DB, n Note) error {
	utils.LogIt("-------------")
	utils.LogIt(fmt.Sprintf("Received key: %s; value: %s", n.Key, n.Value))

	_, err := db.Exec(`
		INSERT OR REPLACE INTO notes(key, value, created_at)
		VALUES ($1, $2, CURRENT_TIMESTAMP)
	`, n.Key, n.Value)
	if err != nil {
		utils.Error_happened(err)
		return err
	}

	utils.LogIt(fmt.Sprintf("%s : %s Saved", n.Key, n.Value))
	return nil
}
