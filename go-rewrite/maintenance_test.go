//go:build sqlite_fts5

package main

import (
	"Go-Butler/dao"
	"Go-Butler/dao/operations"
	"database/sql"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"testing"
	"time"
)

func newTestMaintainer(t *testing.T) (*maintainer, *sql.DB) {
	t.Helper()
	dir := t.TempDir()
	n, err := NewNotesDatabase(dir)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { n.Close() })
	return newMaintainer(n.DB(), dir), n.DB()
}

func mustPutNote(t *testing.T, db *sql.DB, key, value string) {
	t.Helper()
	if err := operations.PutNote(db, dao.Note{Key: key, Value: value}); err != nil {
		t.Fatalf("put %q: %v", key, err)
	}
}

func backupName(at time.Time) string {
	return backupPrefix + at.UTC().Format(backupTimeLayout) + backupSuffix
}

func writeFakeBackups(t *testing.T, dir string, names ...string) {
	t.Helper()
	os.MkdirAll(dir, 0700)
	for _, name := range names {
		if err := os.WriteFile(filepath.Join(dir, name), nil, 0600); err != nil {
			t.Fatal(err)
		}
	}
}

func exists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}

var t0 = time.Date(2026, 10, 18, 9, 30, 0, 0, time.UTC)

// A backup is a standalone copy: notes and search both work when it's opened.
func TestRunIfDue_BackupIsSearchableAndPrivate(t *testing.T) {
	m, db := newTestMaintainer(t)
	mustPutNote(t, db, "wifi", "hunter2 password")

	m.runIfDue(t0)

	backups := listBackups(m.backupDir)
	if len(backups) != 1 || backups[0] != "notes-20261018-093000.db" {
		t.Fatalf("backups = %v", backups)
	}
	path := filepath.Join(m.backupDir, backups[0])
	b, err := sql.Open("sqlite3", path)
	if err != nil {
		t.Fatal(err)
	}
	defer b.Close()
	notes, err := operations.FetchNote(b, "hunt")
	if err != nil || len(notes) != 1 || notes[0].Key != "wifi" {
		t.Fatalf("search in backup = %+v, %v", notes, err)
	}
	if info, _ := os.Stat(path); info.Mode().Perm() != 0600 {
		t.Errorf("backup mode = %v, want 0600", info.Mode().Perm())
	}
	if exists(path + partialSuffix) {
		t.Error("partial file left behind")
	}
}

func TestRunIfDue_SkipsUntilIntervalPassed(t *testing.T) {
	m, _ := newTestMaintainer(t)
	m.runIfDue(t0)
	m.runIfDue(t0.Add(backupInterval - time.Minute))
	if got := len(listBackups(m.backupDir)); got != 1 {
		t.Fatalf("before the interval: %d backups, want 1", got)
	}
	m.runIfDue(t0.Add(backupInterval))
	if got := len(listBackups(m.backupDir)); got != 2 {
		t.Fatalf("after the interval: %d backups, want 2", got)
	}
}

func TestRunIfDue_KeepsNewest(t *testing.T) {
	m, _ := newTestMaintainer(t)
	for i := 0; i < backupsToKeep+3; i++ {
		m.runIfDue(t0.Add(time.Duration(i) * backupInterval))
	}
	backups := listBackups(m.backupDir)
	if len(backups) != backupsToKeep {
		t.Fatalf("%d backups kept, want %d", len(backups), backupsToKeep)
	}
	if want := backupName(t0.Add(time.Duration(backupsToKeep+2) * backupInterval)); backups[len(backups)-1] != want {
		t.Errorf("newest = %s, want %s", backups[len(backups)-1], want)
	}
}

// A copy that fails its check must never be kept, and must not cost any of the
// existing backups; the next attempt waits retryAfterFailure.
func TestRunIfDue_FailedCheckKeepsExistingBackups(t *testing.T) {
	m, _ := newTestMaintainer(t)
	var old []string
	for i := 0; i < backupsToKeep; i++ {
		old = append(old, backupName(t0.Add(-time.Duration(backupsToKeep-i)*backupInterval)))
	}
	writeFakeBackups(t, m.backupDir, old...)
	checks := 0
	m.checkCopy = func(string) (bool, error) { checks++; return false, errors.New("corrupt") }

	m.runIfDue(t0)

	if got := listBackups(m.backupDir); fmt.Sprint(got) != fmt.Sprint(old) {
		t.Errorf("backups changed after a failed check: %v", got)
	}
	if exists(filepath.Join(m.backupDir, backupName(t0)+partialSuffix)) {
		t.Error("rejected copy left behind")
	}
	m.runIfDue(t0.Add(retryAfterFailure - time.Minute))
	if checks != 1 {
		t.Errorf("retried before retryAfterFailure: %d attempts", checks)
	}
	m.runIfDue(t0.Add(retryAfterFailure))
	if checks != 2 {
		t.Errorf("no retry after retryAfterFailure: %d attempts", checks)
	}
}

// If the search index has drifted from the notes, the backup is still made (with
// a rebuilt index) and the live index is repaired.
func TestRunIfDue_DriftedIndexIsBackedUpAndRepaired(t *testing.T) {
	m, db := newTestMaintainer(t)
	mustPutNote(t, db, "indexed", "alpha")
	// Insert a note behind the trigger's back, so the index misses it.
	if _, err := db.Exec("DROP TRIGGER notes_ai"); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec("INSERT INTO notes(key, value) VALUES('missed', 'zebra')"); err != nil {
		t.Fatal(err)
	}
	if ftsInSync(db) {
		t.Fatal("setup: index should be out of sync")
	}

	m.runIfDue(t0)

	backups := listBackups(m.backupDir)
	if len(backups) != 1 {
		t.Fatalf("drifted index blocked the backup: %v", backups)
	}
	b, _ := sql.Open("sqlite3", filepath.Join(m.backupDir, backups[0]))
	defer b.Close()
	if notes, err := operations.FetchNote(b, "zebr"); err != nil || len(notes) != 1 {
		t.Errorf("backup search = %+v, %v", notes, err)
	}
	if notes, err := operations.FetchNote(db, "zebr"); err != nil || len(notes) != 1 {
		t.Errorf("live search not repaired = %+v, %v", notes, err)
	}
}

// A backup dated in the future (wrong clock) must not stop backups, and is
// pruned first.
func TestRunIfDue_FutureDatedBackupDoesNotBlock(t *testing.T) {
	m, _ := newTestMaintainer(t)
	future := backupName(t0.AddDate(1, 0, 0))
	writeFakeBackups(t, m.backupDir, future)

	m.runIfDue(t0)
	if !exists(filepath.Join(m.backupDir, backupName(t0))) {
		t.Fatal("future-dated backup blocked a due backup")
	}
	for i := 1; i < backupsToKeep; i++ {
		m.runIfDue(t0.Add(time.Duration(i) * backupInterval))
	}
	if exists(filepath.Join(m.backupDir, future)) {
		t.Error("future-dated backup survived pruning")
	}
	if got := len(listBackups(m.backupDir)); got != backupsToKeep {
		t.Errorf("%d backups, want %d", got, backupsToKeep)
	}
}

func TestRunIfDue_TightensBackupFolderAndClearsLeftovers(t *testing.T) {
	m, _ := newTestMaintainer(t)
	os.MkdirAll(m.backupDir, 0755)
	leftover := filepath.Join(m.backupDir, "notes-20261001-000000.db"+partialSuffix)
	os.WriteFile(leftover, nil, 0644)

	m.runIfDue(t0)

	if info, _ := os.Stat(m.backupDir); info.Mode().Perm() != 0700 {
		t.Errorf("backup folder mode = %v, want 0700", info.Mode().Perm())
	}
	if exists(leftover) {
		t.Error("leftover .partial not removed")
	}
}

// Files that aren't backups (your own copies, other names) are never deleted.
func TestPruneBackups_IgnoresOtherFiles(t *testing.T) {
	dir := t.TempDir()
	writeFakeBackups(t, dir, "notes-20261001-090000.db", "notes-20261003-090000.db", "my-copy.db", "notes-x.db")
	pruneBackups(dir, 1, t0)
	for _, name := range []string{"notes-20261003-090000.db", "my-copy.db", "notes-x.db"} {
		if !exists(filepath.Join(dir, name)) {
			t.Errorf("%s was deleted", name)
		}
	}
	if exists(filepath.Join(dir, "notes-20261001-090000.db")) {
		t.Error("older backup not pruned")
	}
}

func TestVacuumIfFragmented(t *testing.T) {
	_, db := newTestMaintainer(t)
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

// Maintenance runs alongside requests: saves and searches during a pass must
// all succeed.
func TestRunIfDue_ConcurrentRequestsSucceed(t *testing.T) {
	m, db := newTestMaintainer(t)
	big := fmt.Sprintf("%050000d", 0)
	for i := 0; i < 40; i++ {
		mustPutNote(t, db, fmt.Sprintf("seed%d", i), big)
	}
	db.Exec("DELETE FROM notes WHERE id % 2 = 0") // fragment it, so VACUUM runs too

	var wg sync.WaitGroup
	stop := make(chan struct{})
	errs := make(chan error, 1000)
	wg.Add(1)
	go func() {
		defer wg.Done()
		for i := 0; ; i++ {
			select {
			case <-stop:
				return
			default:
			}
			if err := operations.PutNote(db, dao.Note{Key: fmt.Sprintf("live%d", i), Value: "during maintenance"}); err != nil {
				errs <- fmt.Errorf("put: %w", err)
			}
			if _, err := operations.FetchNote(db, "seed"); err != nil {
				errs <- fmt.Errorf("fetch: %w", err)
			}
		}
	}()
	for i := 0; i < 3; i++ {
		m.runIfDue(t0.Add(time.Duration(i) * backupInterval))
	}
	close(stop)
	wg.Wait()
	close(errs)
	for err := range errs {
		t.Error(err)
	}
	if got := len(listBackups(m.backupDir)); got != 3 {
		t.Errorf("%d backups, want 3", got)
	}
}
