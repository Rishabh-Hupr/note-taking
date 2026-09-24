//go:build sqlite_fts5

package processor

import (
	"bufio"
	"bytes"
	"database/sql"
	"path/filepath"
	"strings"
	"testing"

	_ "github.com/mattn/go-sqlite3"
)

// newTestDB opens a fresh SQLite DB with the notes schema (mirrors
// setup_database.go). NewNotesDatabase lives in package main, which can't be
// imported, so the schema is recreated here.
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

func TestHandler_Ping(t *testing.T) {
	resp := handler(newTestDB(t), Request{ID: 1, Cmd: "ping"})
	if !resp.OK || resp.ID != 1 {
		t.Errorf("ping resp = %+v", resp)
	}
}

func TestHandler_PutThenFetchAndList(t *testing.T) {
	db := newTestDB(t)
	if r := handler(db, Request{ID: 1, Cmd: "put", Key: "wifi", Value: "hunter2"}); !r.OK {
		t.Fatalf("put: %+v", r)
	}
	r := handler(db, Request{ID: 2, Cmd: "fetch", Query: "wifi"})
	if !r.OK || len(r.Notes) == 0 || r.Notes[0].Key != "wifi" {
		t.Errorf("fetch: %+v", r)
	}
	l := handler(db, Request{ID: 3, Cmd: "list"})
	if !l.OK || len(l.Notes) != 1 {
		t.Errorf("list: %+v", l)
	}
}

func TestHandler_PutMissingFields(t *testing.T) {
	r := handler(newTestDB(t), Request{ID: 1, Cmd: "put", Key: "onlykey"})
	if r.OK || r.Error == "" {
		t.Errorf("expected error for missing value, got %+v", r)
	}
}

func TestHandler_UnknownCmd(t *testing.T) {
	r := handler(newTestDB(t), Request{ID: 9, Cmd: "bogus"})
	if r.OK || !strings.Contains(r.Error, "unknown cmd") {
		t.Errorf("expected unknown cmd error, got %+v", r)
	}
}

func TestHandler_FetchEmptyListsAll(t *testing.T) {
	db := newTestDB(t)
	handler(db, Request{ID: 1, Cmd: "put", Key: "a", Value: "1"})
	handler(db, Request{ID: 2, Cmd: "put", Key: "b", Value: "2"})
	r := handler(db, Request{ID: 3, Cmd: "fetch", Query: ""})
	if !r.OK || len(r.Notes) != 2 {
		t.Errorf("empty fetch should list all, got ok=%v notes=%d", r.OK, len(r.Notes))
	}
}

func TestSafeHandler_RecoversPanic(t *testing.T) {
	// A nil *sql.DB makes ShowDB nil-deref inside handler → panic. SafeHandler
	// must turn that into an error response instead of crashing.
	r := SafeHandler(nil, Request{ID: 7, Cmd: "list"})
	if r.OK {
		t.Fatal("expected failure from panic recovery")
	}
	if r.ID != 7 {
		t.Errorf("id=%d want 7 (should echo request id)", r.ID)
	}
	if !strings.Contains(r.Error, "internal error") {
		t.Errorf("error=%q want an 'internal error' message", r.Error)
	}
}

func TestSafeHandler_NormalPassthrough(t *testing.T) {
	r := SafeHandler(newTestDB(t), Request{ID: 1, Cmd: "ping"})
	if !r.OK {
		t.Errorf("ping through SafeHandler: %+v", r)
	}
}

func TestWriteResponse(t *testing.T) {
	var buf bytes.Buffer
	w := bufio.NewWriter(&buf)
	WriteResponse(w, Response{ID: 5, OK: true})
	if got, want := buf.String(), `{"id":5,"ok":true}`+"\n"; got != want {
		t.Errorf("WriteResponse = %q want %q", got, want)
	}
}
