//go:build sqlite_fts5

package operations

import "testing"

func TestDeleteNote_RemovesByID(t *testing.T) {
	db := newTestDB(t)
	mustPut(t, db, "keep", "stays")
	mustPut(t, db, "drop", "goes away")

	target, ok := findNote(mustShow(t, db), "drop")
	if !ok {
		t.Fatal("setup: drop note missing")
	}

	if err := DeleteNote(db, target.Id); err != nil {
		t.Fatalf("delete: %v", err)
	}

	notes := mustShow(t, db)
	if _, ok := findNote(notes, "drop"); ok {
		t.Error("deleted note is still present")
	}
	if _, ok := findNote(notes, "keep"); !ok {
		t.Error("unrelated note should remain")
	}
	if len(notes) != 1 {
		t.Errorf("want 1 note left, got %d", len(notes))
	}
}

// Deletion must also clear the FTS index (via the notes_ad trigger), otherwise a
// deleted note would still surface in search results.
func TestDeleteNote_AlsoRemovesFromFTS(t *testing.T) {
	db := newTestDB(t)
	mustPut(t, db, "wifi", "hunter2 password")

	target, ok := findNote(mustShow(t, db), "wifi")
	if !ok {
		t.Fatal("setup: wifi note missing")
	}
	if err := DeleteNote(db, target.Id); err != nil {
		t.Fatalf("delete: %v", err)
	}

	notes, err := FetchNote(db, "hunter2")
	if err != nil {
		t.Fatalf("fetch: %v", err)
	}
	if len(notes) != 0 {
		t.Errorf("deleted note should not be searchable, got %+v", notes)
	}
}

func TestDeleteNote_MissingIDIsNoOp(t *testing.T) {
	db := newTestDB(t)
	mustPut(t, db, "a", "1")

	if err := DeleteNote(db, 9999); err != nil {
		t.Errorf("deleting a nonexistent id should be a no-op, got %v", err)
	}
	if n := len(mustShow(t, db)); n != 1 {
		t.Errorf("no-op delete should leave the table unchanged, got %d notes", n)
	}
}
