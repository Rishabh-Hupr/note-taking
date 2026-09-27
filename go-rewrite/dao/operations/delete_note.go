package operations

import (
	"Go-Butler/helpers"
	"database/sql"
	"fmt"
)

// DeleteNote removes the note with the given id. Id is the stable primary key, so
// deletion is unambiguous even if two notes ever shared a key. The note is looked
// up first so the log records what was removed (key + value), not just an opaque
// id. The notes_ad trigger keeps the FTS index in sync, so a plain DELETE is
// enough. Deleting an id that doesn't exist is not an error — the end state is
// the same either way.
func DeleteNote(db *sql.DB, id int) error {
	helpers.LogIt("-------------")

	var key, value string
	err := db.QueryRow(`SELECT key, value FROM notes WHERE id = ?`, id).Scan(&key, &value)
	switch {
	case err == sql.ErrNoRows:
		helpers.LogIt(fmt.Sprintf("Delete id %d: no such note, nothing to do", id))
		return nil
	case err != nil:
		helpers.Error_happened(err)
		return err
	}

	helpers.LogIt(fmt.Sprintf("Deleting id %d; key: %s; value: %s", id, key, value))

	if _, err := db.Exec(`DELETE FROM notes WHERE id = ?`, id); err != nil {
		helpers.Error_happened(err)
		return err
	}

	helpers.LogIt(fmt.Sprintf("id %d (%s) deleted", id, key))
	return nil
}
