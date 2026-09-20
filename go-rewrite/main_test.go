//go:build sqlite_fts5

package main

import (
	"bufio"
	"bytes"
	"database/sql"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// testDB builds a real DB with the production schema via NewNotesDatabase.
func testDB(t *testing.T) *sql.DB {
	t.Helper()
	ndb, err := NewNotesDatabase(t.TempDir())
	if err != nil {
		t.Fatalf("new db: %v", err)
	}
	t.Cleanup(func() { ndb.db.Close() })
	return ndb.DB()
}

func TestDataDir_EnvOverride(t *testing.T) {
	t.Setenv("BUTLER_DATA_DIR", "/tmp/butler-test-xyz")
	got, err := dataDir()
	if err != nil {
		t.Fatal(err)
	}
	if got != "/tmp/butler-test-xyz" {
		t.Errorf("dataDir=%q want /tmp/butler-test-xyz", got)
	}
}

func TestDataDir_DefaultsToDotButler(t *testing.T) {
	t.Setenv("BUTLER_DATA_DIR", "")
	got, err := dataDir()
	if err != nil {
		t.Fatal(err)
	}
	home, err := os.UserHomeDir()
	if err != nil {
		t.Fatal(err)
	}
	if want := filepath.Join(home, ".butler"); got != want {
		t.Errorf("dataDir=%q want %q", got, want)
	}
}

func TestHandle_Ping(t *testing.T) {
	resp := handle(testDB(t), request{ID: 1, Cmd: "ping"})
	if !resp.OK || resp.ID != 1 {
		t.Errorf("ping resp = %+v", resp)
	}
}

func TestHandle_PutThenFetchAndList(t *testing.T) {
	db := testDB(t)
	if r := handle(db, request{ID: 1, Cmd: "put", Key: "wifi", Value: "hunter2"}); !r.OK {
		t.Fatalf("put: %+v", r)
	}
	r := handle(db, request{ID: 2, Cmd: "fetch", Query: "wifi"})
	if !r.OK || len(r.Notes) == 0 || r.Notes[0].Key != "wifi" {
		t.Errorf("fetch: %+v", r)
	}
	l := handle(db, request{ID: 3, Cmd: "list"})
	if !l.OK || len(l.Notes) != 1 {
		t.Errorf("list: %+v", l)
	}
}

func TestHandle_PutMissingFields(t *testing.T) {
	r := handle(testDB(t), request{ID: 1, Cmd: "put", Key: "onlykey"})
	if r.OK || r.Error == "" {
		t.Errorf("expected error for missing value, got %+v", r)
	}
}

func TestHandle_UnknownCmd(t *testing.T) {
	r := handle(testDB(t), request{ID: 9, Cmd: "bogus"})
	if r.OK || !strings.Contains(r.Error, "unknown cmd") {
		t.Errorf("expected unknown cmd error, got %+v", r)
	}
}

func TestSafeHandle_RecoversPanic(t *testing.T) {
	// A nil *sql.DB makes dao.ShowDB nil-deref inside handle → panic. safeHandle
	// must turn that into an error response instead of crashing.
	r := safeHandle(nil, request{ID: 7, Cmd: "list"})
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

func TestSafeHandle_NormalPassthrough(t *testing.T) {
	r := safeHandle(testDB(t), request{ID: 1, Cmd: "ping"})
	if !r.OK {
		t.Errorf("ping through safeHandle: %+v", r)
	}
}

func TestWriteResp(t *testing.T) {
	var buf bytes.Buffer
	w := bufio.NewWriter(&buf)
	writeResp(w, response{ID: 5, OK: true})
	if got, want := buf.String(), `{"id":5,"ok":true}`+"\n"; got != want {
		t.Errorf("writeResp = %q want %q", got, want)
	}
}
