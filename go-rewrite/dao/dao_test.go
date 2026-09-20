//go:build sqlite_fts5

package dao

import (
	"database/sql"
	"path/filepath"
	"strings"
	"testing"

	_ "github.com/mattn/go-sqlite3"
)

// newTestDB opens a fresh SQLite DB with the notes schema. The schema mirrors
// setup_database.go (source of truth) and is kept in sync manually.
func newTestDB(t *testing.T) *sql.DB {
	t.Helper()
	db, err := sql.Open("sqlite3", filepath.Join(t.TempDir(), "test.db"))
	if err != nil {
		t.Fatalf("open db: %v", err)
	}
	t.Cleanup(func() { db.Close() })

	stmts := []string{
		`CREATE TABLE notes (
			id INTEGER PRIMARY KEY,
			key TEXT UNIQUE NOT NULL,
			value TEXT NOT NULL,
			created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
			updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
		)`,
		`CREATE VIRTUAL TABLE notes_fts USING FTS5(key, value, content='notes', content_rowid='id', prefix='2 3 4 5 6')`,
		`CREATE TRIGGER notes_ai AFTER INSERT ON notes BEGIN
			INSERT INTO notes_fts(rowid, key, value) VALUES (new.id, new.key, new.value);
		END`,
		`CREATE TRIGGER notes_ad AFTER DELETE ON notes BEGIN
			INSERT INTO notes_fts(notes_fts, rowid, key, value) VALUES('delete', old.id, old.key, old.value);
		END`,
		`CREATE TRIGGER notes_au AFTER UPDATE ON notes BEGIN
			INSERT INTO notes_fts(notes_fts, rowid, key, value) VALUES('delete', old.id, old.key, old.value);
			INSERT INTO notes_fts(rowid, key, value) VALUES (new.id, new.key, new.value);
		END`,
	}
	for _, s := range stmts {
		if _, err := db.Exec(s); err != nil {
			t.Fatalf("schema exec: %v", err)
		}
	}
	return db
}

func findNote(notes []Note, key string) (Note, bool) {
	for _, n := range notes {
		if n.Key == key {
			return n, true
		}
	}
	return Note{}, false
}

func TestPutNote_InsertSetsEqualTimestamps(t *testing.T) {
	db := newTestDB(t)
	if err := PutNote(db, Note{Key: "wifi", Value: "hunter2"}); err != nil {
		t.Fatalf("put: %v", err)
	}
	notes, err := ShowDB(db)
	if err != nil {
		t.Fatalf("show: %v", err)
	}
	n, ok := findNote(notes, "wifi")
	if !ok {
		t.Fatal("note not found after put")
	}
	if n.Value != "hunter2" {
		t.Errorf("value=%q want hunter2", n.Value)
	}
	if n.CreatedAt == "" || n.UpdatedAt == "" {
		t.Fatalf("timestamps empty: created=%q updated=%q", n.CreatedAt, n.UpdatedAt)
	}
	if n.CreatedAt != n.UpdatedAt {
		t.Errorf("on insert created(%s) should equal updated(%s)", n.CreatedAt, n.UpdatedAt)
	}
}

func TestPutNote_UpsertPreservesCreatedBumpsUpdated(t *testing.T) {
	db := newTestDB(t)
	if err := PutNote(db, Note{Key: "k1", Value: "first"}); err != nil {
		t.Fatal(err)
	}
	// Pin timestamps to a known past value so the assertion doesn't depend on a
	// wall-clock gap between the two puts.
	if _, err := db.Exec(`UPDATE notes SET created_at='2000-01-01 00:00:00', updated_at='2000-01-01 00:00:00' WHERE key='k1'`); err != nil {
		t.Fatal(err)
	}
	if err := PutNote(db, Note{Key: "k1", Value: "second"}); err != nil {
		t.Fatal(err)
	}

	n, ok := findNote(mustShow(t, db), "k1")
	if !ok {
		t.Fatal("missing note")
	}
	if n.Value != "second" {
		t.Errorf("value=%q want second (upsert should update value)", n.Value)
	}
	if !strings.Contains(n.CreatedAt, "2000-01-01") {
		t.Errorf("created_at should be preserved from first insert, got %q", n.CreatedAt)
	}
	if strings.Contains(n.UpdatedAt, "2000") {
		t.Errorf("updated_at should be bumped away from the pinned 2000 value, got %q", n.UpdatedAt)
	}
}

func TestFetchNote_SearchesKeyAndValue(t *testing.T) {
	db := newTestDB(t)
	mustPut(t, db, "wifi", "hunter2 password")
	mustPut(t, db, "deploy", "run anyconnect script")

	// prefix match on the key
	if notes, err := FetchNote(db, "wif"); err != nil {
		t.Fatalf("key search err: %v", err)
	} else if _, ok := findNote(notes, "wifi"); !ok {
		t.Errorf("expected wifi via key search, got %+v", notes)
	}
	// match on a word only present in the value
	if notes, err := FetchNote(db, "anyconnect"); err != nil {
		t.Fatalf("value search err: %v", err)
	} else if _, ok := findNote(notes, "deploy"); !ok {
		t.Errorf("expected deploy via value search, got %+v", notes)
	}
}

func TestFetchNote_SpecialCharsDoNotError(t *testing.T) {
	db := newTestDB(t)
	mustPut(t, db, "k", "v")
	if _, err := FetchNote(db, `weird:input-with"quote`); err != nil {
		t.Errorf("special-char query should not error: %v", err)
	}
}

func TestFetchLike_FindsByValueSubstring(t *testing.T) {
	db := newTestDB(t)
	mustPut(t, db, "alpha", "beta gamma")
	notes, err := fetchLike(db, "gamma")
	if err != nil {
		t.Fatalf("fetchLike err: %v", err)
	}
	if _, ok := findNote(notes, "alpha"); !ok {
		t.Errorf("fetchLike should find by value substring, got %+v", notes)
	}
}

func TestShowDB_OrdersByUpdatedDesc(t *testing.T) {
	db := newTestDB(t)
	mustPut(t, db, "old", "x")
	mustPut(t, db, "new", "y")
	// Force a deterministic ordering by updated_at.
	if _, err := db.Exec(`UPDATE notes SET updated_at='2000-01-01 00:00:00' WHERE key='old'`); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`UPDATE notes SET updated_at='2030-01-01 00:00:00' WHERE key='new'`); err != nil {
		t.Fatal(err)
	}
	notes := mustShow(t, db)
	if len(notes) < 2 {
		t.Fatalf("want 2 notes, got %d", len(notes))
	}
	if notes[0].Key != "new" {
		t.Errorf("expected most-recently-updated first, got %q", notes[0].Key)
	}
}

func TestFetchNote_EmptyQueryListsAll(t *testing.T) {
	db := newTestDB(t)
	mustPut(t, db, "a", "one")
	mustPut(t, db, "b", "two")

	for _, q := range []string{"", "   "} {
		notes, err := FetchNote(db, q)
		if err != nil {
			t.Fatalf("empty fetch %q err: %v", q, err)
		}
		if len(notes) != 2 {
			t.Errorf("empty query %q should list all (2), got %d", q, len(notes))
		}
	}
}

func TestFetchLike_EscapesWildcards(t *testing.T) {
	db := newTestDB(t)
	mustPut(t, db, "alpha", "beta")
	mustPut(t, db, "gamma", "delta")

	// No note contains a literal '%' or '_'. With proper escaping these queries
	// match nothing; without it they'd behave as wildcards and match everything.
	for _, q := range []string{"%", "_"} {
		notes, err := fetchLike(db, q)
		if err != nil {
			t.Fatalf("fetchLike %q err: %v", q, err)
		}
		if len(notes) != 0 {
			t.Errorf("fetchLike(%q) should match literally (0 results), got %d", q, len(notes))
		}
	}
}

func mustPut(t *testing.T, db *sql.DB, key, value string) {
	t.Helper()
	if err := PutNote(db, Note{Key: key, Value: value}); err != nil {
		t.Fatalf("put %q: %v", key, err)
	}
}

func mustShow(t *testing.T, db *sql.DB) []Note {
	t.Helper()
	notes, err := ShowDB(db)
	if err != nil {
		t.Fatalf("show: %v", err)
	}
	return notes
}
