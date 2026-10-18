//go:build sqlite_fts5

package main

import (
	"Go-Butler/dao"
	"Go-Butler/dao/operations"
	"database/sql"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func newMaintenanceDB(t *testing.T) (*sql.DB, string) {
	t.Helper()
	dir := t.TempDir()
	n, err := NewNotesDatabase(dir)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { n.Close() })
	return n.DB(), dir
}

func mustPutNote(t *testing.T, db *sql.DB, key, value string) {
	t.Helper()
	if err := operations.PutNote(db, dao.Note{Key: key, Value: value}); err != nil {
		t.Fatalf("put %q: %v", key, err)
	}
}

// A backup is a standalone copy: notes and search index both work when opened.
func TestMaintainIfDue_BackupIsSearchable(t *testing.T) {
	db, dir := newMaintenanceDB(t)
	mustPutNote(t, db, "wifi", "hunter2 password")
	now := time.Date(2026, 10, 18, 9, 30, 0, 0, time.Local)

	maintainIfDue(db, dir, now)

	backupDir := filepath.Join(dir, backupDirName)
	backups := listBackups(backupDir)
	if len(backups) != 1 || backups[0] != "notes-20261018-093000.db" {
		t.Fatalf("backups = %v", backups)
	}
	// Open the backup itself, as it would be used after a restore.
	b, err := sql.Open("sqlite3", filepath.Join(backupDir, backups[0]))
	if err != nil {
		t.Fatal(err)
	}
	defer b.Close()
	notes, err := operations.FetchNote(b, "hunt")
	if err != nil || len(notes) != 1 || notes[0].Key != "wifi" {
		t.Fatalf("search in backup = %+v, %v", notes, err)
	}
	if info, _ := os.Stat(filepath.Join(backupDir, backups[0])); info.Mode().Perm() != 0600 {
		t.Errorf("backup mode = %v, want 0600", info.Mode().Perm())
	}
	if _, err := os.Stat(filepath.Join(backupDir, backups[0]+".partial")); !os.IsNotExist(err) {
		t.Error("partial file left behind")
	}
}

func TestMaintainIfDue_SkipsUntilIntervalPassed(t *testing.T) {
	db, dir := newMaintenanceDB(t)
	start := time.Date(2026, 10, 18, 9, 0, 0, 0, time.Local)

	maintainIfDue(db, dir, start)
	maintainIfDue(db, dir, start.Add(maintenanceInterval-time.Minute))
	if got := len(listBackups(filepath.Join(dir, backupDirName))); got != 1 {
		t.Fatalf("before the interval: %d backups, want 1", got)
	}
	maintainIfDue(db, dir, start.Add(maintenanceInterval))
	if got := len(listBackups(filepath.Join(dir, backupDirName))); got != 2 {
		t.Fatalf("after the interval: %d backups, want 2", got)
	}
}

func TestMaintainIfDue_KeepsNewest(t *testing.T) {
	db, dir := newMaintenanceDB(t)
	start := time.Date(2026, 10, 1, 9, 0, 0, 0, time.Local)
	for i := 0; i < backupsToKeep+3; i++ {
		maintainIfDue(db, dir, start.Add(time.Duration(i)*maintenanceInterval))
	}
	backups := listBackups(filepath.Join(dir, backupDirName))
	if len(backups) != backupsToKeep {
		t.Fatalf("%d backups kept, want %d", len(backups), backupsToKeep)
	}
	newest := start.Add(time.Duration(backupsToKeep+2) * maintenanceInterval)
	if want := backupPrefix + newest.Format(backupTimeLayout) + backupSuffix; backups[len(backups)-1] != want {
		t.Errorf("newest = %s, want %s", backups[len(backups)-1], want)
	}
}

// Files that aren't backups (the user's own copies, leftovers) are never deleted.
func TestPruneBackups_IgnoresOtherFiles(t *testing.T) {
	dir := t.TempDir()
	for _, name := range []string{"notes-20261001-090000.db", "notes-20261003-090000.db", "my-copy.db", "notes-x.db"} {
		os.WriteFile(filepath.Join(dir, name), nil, 0600)
	}
	pruneBackups(dir, 1)
	for _, name := range []string{"notes-20261003-090000.db", "my-copy.db", "notes-x.db"} {
		if _, err := os.Stat(filepath.Join(dir, name)); err != nil {
			t.Errorf("%s was deleted", name)
		}
	}
	if _, err := os.Stat(filepath.Join(dir, "notes-20261001-090000.db")); !os.IsNotExist(err) {
		t.Error("older backup not pruned")
	}
}

func TestVacuumIfFragmented(t *testing.T) {
	db, _ := newMaintenanceDB(t)
	big := fmt.Sprintf("%0100000d", 0) // ~100KB per note, so deletes free many pages
	for i := 0; i < 5; i++ {
		mustPutNote(t, db, fmt.Sprintf("k%d", i), big)
	}
	if vacuumed, err := vacuumIfFragmented(db); err != nil || vacuumed {
		t.Fatalf("no free pages: vacuumed=%v err=%v", vacuumed, err)
	}
	if _, err := db.Exec("DELETE FROM notes WHERE key != 'k0'"); err != nil {
		t.Fatal(err)
	}
	if vacuumed, err := vacuumIfFragmented(db); err != nil || !vacuumed {
		t.Fatalf("mostly free: vacuumed=%v err=%v", vacuumed, err)
	}
	var free int64
	db.QueryRow("PRAGMA freelist_count").Scan(&free)
	if free != 0 {
		t.Errorf("freelist_count after VACUUM = %d", free)
	}
}

func TestOptimizeFTS_KeepsSearchWorking(t *testing.T) {
	db, _ := newMaintenanceDB(t)
	for i := 0; i < 20; i++ {
		mustPutNote(t, db, fmt.Sprintf("note%d", i), "alpha beta")
	}
	if err := optimizeFTS(db); err != nil {
		t.Fatal(err)
	}
	notes, err := operations.FetchNote(db, "alph")
	if err != nil || len(notes) != 20 {
		t.Fatalf("after optimize: %d notes, %v", len(notes), err)
	}
}

func TestReadLines_SkipsBlankLinesAndClosesAtEOF(t *testing.T) {
	lines := make(chan []byte)
	go readLines(strings.NewReader("{\"id\":1}\n\n  \n{\"id\":2}"), lines)
	var got []string
	for line := range lines {
		got = append(got, string(line))
	}
	if len(got) != 2 || got[0] != `{"id":1}` || got[1] != `{"id":2}` {
		t.Errorf("lines = %q", got)
	}
}
