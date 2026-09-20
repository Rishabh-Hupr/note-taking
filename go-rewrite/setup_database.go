//go:build sqlite_fts5
// +build sqlite_fts5

package main

import (
	"database/sql"
	"fmt"
	"os"

	_ "github.com/mattn/go-sqlite3"
)

type NotesDatabase struct {
	db *sql.DB
}

// DB exposes the underlying handle for the dao layer.
func (n *NotesDatabase) DB() *sql.DB { return n.db }

func NewNotesDatabase(dbPath string) (*NotesDatabase, error) {
	// Create the directory if it doesn't exist
	if _, err := os.Stat(dbPath); os.IsNotExist(err) {
		if err := os.MkdirAll(dbPath, 0755); err != nil {
			return nil, fmt.Errorf("error creating database directory: %v", err)
		}
	}

	DBFile := dbPath + "/notes.db"

	// Open or create the database
	db, err := sql.Open("sqlite3", DBFile)
	if err != nil {
		return nil, fmt.Errorf("error opening database: %v", err)
	}

	// Enable foreign keys and WAL mode
	_, err = db.Exec("PRAGMA foreign_keys = ON")
	if err != nil {
		return nil, fmt.Errorf("error enabling foreign keys: %v", err)
	}

	_, err = db.Exec("PRAGMA journal_mode = WAL")
	if err != nil {
		return nil, fmt.Errorf("error setting journal mode: %v", err)
	}

	// Create the necessary tables
	if err := createTables(db); err != nil {
		return nil, err
	}

	return &NotesDatabase{db: db}, nil
}

func createTables(db *sql.DB) error {
	// Main notes table
	_, err := db.Exec(`
		CREATE TABLE IF NOT EXISTS notes (
			id INTEGER PRIMARY KEY,
			key TEXT UNIQUE NOT NULL,
			value TEXT NOT NULL,
			created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
			updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
		)
	`)
	if err != nil {
		return fmt.Errorf("error creating notes table: %v", err)
	}

	// FTS5 virtual table for full-text search
	_, err = db.Exec(`
		CREATE VIRTUAL TABLE IF NOT EXISTS notes_fts 
		USING FTS5(key, value, content='notes', content_rowid='id', prefix='2 3 4 5 6');
	`)
	if err != nil {
		return fmt.Errorf("error creating FTS5 table: %v", err)
	}

	// Triggers to keep the FTS index updated
	_, err = db.Exec(`
		CREATE TRIGGER IF NOT EXISTS notes_ai AFTER INSERT ON notes BEGIN
			INSERT INTO notes_fts(rowid, key, value) VALUES (new.id, new.key, new.value);
		END;
		
		CREATE TRIGGER IF NOT EXISTS notes_ad AFTER DELETE ON notes BEGIN
			INSERT INTO notes_fts(notes_fts, rowid, key, value) VALUES('delete', old.id, old.key, old.value);
		END;
		
		CREATE TRIGGER IF NOT EXISTS notes_au AFTER UPDATE ON notes BEGIN
			INSERT INTO notes_fts(notes_fts, rowid, key, value) VALUES('delete', old.id, old.key, old.value);
			INSERT INTO notes_fts(rowid, key, value) VALUES (new.id, new.key, new.value);
		END;
	`)
	if err != nil {
		return fmt.Errorf("error creating triggers: %v", err)
	}

	return nil
}

func (db *NotesDatabase) RebuildFTSTable(prefix string) error {
	// Drop the old FTS table if it exists
	_, err := db.db.Exec("DROP TABLE IF EXISTS notes_fts")
	if err != nil {
		return fmt.Errorf("error dropping FTS table: %v", err)
	}

	// Create a new FTS table with the provided prefix
	_, err = db.db.Exec(fmt.Sprintf(`
		CREATE VIRTUAL TABLE notes_fts 
		USING FTS5(key, value, content='notes', content_rowid='id', prefix='%s')
	`, prefix))
	if err != nil {
		return fmt.Errorf("error creating new FTS table: %v", err)
	}

	// Create triggers to keep the FTS table updated
	_, err = db.db.Exec(`
		CREATE TRIGGER IF NOT EXISTS notes_ai AFTER INSERT ON notes BEGIN
			INSERT INTO notes_fts(rowid, key, value) VALUES (new.id, new.key, new.value);
		END;

		CREATE TRIGGER IF NOT EXISTS notes_ad AFTER DELETE ON notes BEGIN
			INSERT INTO notes_fts(notes_fts, rowid, key, value) VALUES('delete', old.id, old.key, old.value);
		END;

		CREATE TRIGGER IF NOT EXISTS notes_au AFTER UPDATE ON notes BEGIN
			INSERT INTO notes_fts(notes_fts, rowid, key, value) VALUES('delete', old.id, old.key, old.value);
			INSERT INTO notes_fts(rowid, key, value) VALUES (new.id, new.key, new.value);
		END;
	`)
	if err != nil {
		return fmt.Errorf("error creating rebuild triggers: %v", err)
	}

	// Rebuild the FTS table
	_, err = db.db.Exec("INSERT INTO notes_fts(notes_fts) VALUES('rebuild')")
	if err != nil {
		return fmt.Errorf("error rebuilding FTS table: %v", err)
	}

	return nil
}

// func main() {
// 	// Initialize the database
// 	db, err := NewNotesDatabase(DBPath)
// 	if err != nil {
// 		fmt.Println("Error initializing database:", err)
// 		return
// 	}
// 	defer db.db.Close()

// 	// Uncomment below to rebuild the FTS table
// 	// if err := db.RebuildFTSTable("2 3 4 5"); err != nil {
// 	//	fmt.Println("Error rebuilding FTS table:", err)
// 	// }
// }
