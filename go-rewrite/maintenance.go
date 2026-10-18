//go:build sqlite_fts5
// +build sqlite_fts5

package main

import (
	"Go-Butler/helpers"
	"database/sql"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

// Database backups and upkeep. A background goroutine checks firstCheckDelay
// after start and then every checkEvery; a pass runs when the newest backup is
// at least backupInterval old (or there is none), and after a failed pass waits
// retryAfterFailure before trying again. A pass:
//  1. Backs up first, before touching the live database: VACUUM INTO a complete,
//     standalone copy (notes, search index, triggers) in <data dir>/backups/.
//     The copy must pass quick_check; if only its search index is out of sync
//     with its notes, the index is rebuilt in the copy. Only then is it named
//     and kept. The newest backupsToKeep are kept.
//  2. Upkeep on the live database: rebuilds the search index if the copy showed
//     it was out of sync, otherwise FTS5 optimize; then VACUUM when at least
//     vacuumFreeRatio of the file is free pages.
//
// Searches carry on during a pass (WAL readers aren't blocked). Saves wait only
// while a write step runs (go-sqlite3's default 5s busy timeout covers it).
// Restoring a backup is manual: RUNBOOK.md.
const (
	backupInterval    = 48 * time.Hour
	backupsToKeep     = 7
	vacuumFreeRatio   = 0.2
	firstCheckDelay   = 30 * time.Second // never during startup
	checkEvery        = time.Hour        // the backend can run for days
	retryAfterFailure = 6 * time.Hour

	backupDirName    = "backups"
	backupPrefix     = "notes-"
	backupSuffix     = ".db"
	partialSuffix    = ".partial"
	backupTimeLayout = "20060102-150405" // UTC, so names sort chronologically as text
)

type maintainer struct {
	db          *sql.DB
	backupDir   string
	lastFailure time.Time
	// The check a fresh copy must pass; a field so tests can make it fail.
	checkCopy func(path string) (indexRebuilt bool, err error)
}

func newMaintainer(db *sql.DB, dataDir string) *maintainer {
	return &maintainer{db: db, backupDir: filepath.Join(dataDir, backupDirName), checkCopy: checkCopy}
}

// run checks for due maintenance forever. One goroutine, so passes never overlap.
func (m *maintainer) run() {
	time.Sleep(firstCheckDelay)
	for {
		m.runIfDue(time.Now())
		time.Sleep(checkEvery)
	}
}

// runIfDue runs a pass if one is due. Cheap when not: one directory read.
func (m *maintainer) runIfDue(now time.Time) {
	if !m.due(now) {
		return
	}
	start := time.Now()
	if err := m.pass(now); err != nil {
		m.lastFailure = now
		helpers.LogIt(fmt.Sprintf("maintenance: %v (retrying in %s)", err, retryAfterFailure))
	}
	helpers.LogIt(fmt.Sprintf("maintenance: done in %dms", time.Since(start).Milliseconds()))
}

func (m *maintainer) due(now time.Time) bool {
	if !m.lastFailure.IsZero() && now.Sub(m.lastFailure) < retryAfterFailure {
		return false
	}
	last, ok := newestBackupTime(listBackups(m.backupDir), now)
	return !ok || now.Sub(last) >= backupInterval
}

func (m *maintainer) pass(now time.Time) error {
	name, indexRebuilt, err := m.backup(now)
	if err != nil {
		return fmt.Errorf("backup failed: %w", err)
	}
	pruneBackups(m.backupDir, backupsToKeep, now)
	helpers.LogIt("maintenance: backed up to " + name)

	// The backup is safe on disk; now tidy the live database.
	if indexRebuilt {
		helpers.LogIt("maintenance: search index was out of sync with the notes; rebuilding it")
		if _, err := m.db.Exec("INSERT INTO notes_fts(notes_fts) VALUES('rebuild')"); err != nil {
			return fmt.Errorf("search index rebuild failed: %w", err)
		}
	} else if _, err := m.db.Exec("INSERT INTO notes_fts(notes_fts) VALUES('optimize')"); err != nil {
		return fmt.Errorf("search index optimize failed: %w", err)
	}
	vacuumed, err := vacuumIfFragmented(m.db)
	if err != nil {
		return fmt.Errorf("VACUUM failed: %w", err)
	}
	if vacuumed {
		helpers.LogIt("maintenance: VACUUM reclaimed free pages")
	}
	return nil
}

// backup writes a snapshot as a .partial file, checks it, and only then gives it
// its final name, so every listed backup is a good one.
func (m *maintainer) backup(now time.Time) (name string, indexRebuilt bool, err error) {
	if err := os.MkdirAll(m.backupDir, 0700); err != nil {
		return "", false, err
	}
	// Private even if the folder was created by hand: the copy is written with the
	// default umask and is only chmod-ed after its checks.
	if err := os.Chmod(m.backupDir, 0700); err != nil {
		return "", false, err
	}
	removePartials(m.backupDir) // leftovers from a pass cut short by a quit
	name = backupPrefix + now.UTC().Format(backupTimeLayout) + backupSuffix
	final := filepath.Join(m.backupDir, name)
	partial := final + partialSuffix
	if _, err := m.db.Exec("VACUUM INTO ?", partial); err != nil {
		os.Remove(partial)
		return "", false, err
	}
	if indexRebuilt, err = m.checkCopy(partial); err != nil {
		os.Remove(partial)
		return "", false, fmt.Errorf("copy failed its check: %w", err)
	}
	if err := os.Chmod(partial, 0600); err != nil {
		os.Remove(partial)
		return "", false, err
	}
	if err := os.Rename(partial, final); err != nil {
		os.Remove(partial)
		return "", false, err
	}
	return name, indexRebuilt, nil
}

// checkCopy verifies a fresh copy. A damaged file is rejected; a search index
// that is merely out of sync with the notes (the notes are what matter) is
// rebuilt from them, and indexRebuilt tells the caller the live one needs it too.
func checkCopy(path string) (indexRebuilt bool, err error) {
	c, err := sql.Open("sqlite3", path)
	if err != nil {
		return false, err
	}
	defer c.Close()
	var result string
	if err := c.QueryRow("PRAGMA quick_check").Scan(&result); err != nil {
		return false, err
	}
	if result != "ok" {
		return false, errors.New("quick_check: " + result)
	}
	if ftsInSync(c) {
		return false, nil
	}
	if _, err := c.Exec("INSERT INTO notes_fts(notes_fts) VALUES('rebuild')"); err != nil {
		return false, err
	}
	if !ftsInSync(c) {
		return false, errors.New("search index still out of sync after rebuild")
	}
	return true, nil
}

// ftsInSync runs FTS5's integrity-check, which errors if the index doesn't match
// the notes table.
func ftsInSync(db *sql.DB) bool {
	_, err := db.Exec("INSERT INTO notes_fts(notes_fts, rank) VALUES('integrity-check', 1)")
	return err == nil
}

// vacuumIfFragmented rebuilds the file when at least vacuumFreeRatio of its
// pages are free (left behind by deletes and edits).
func vacuumIfFragmented(db *sql.DB) (bool, error) {
	var pages, free int64
	if err := db.QueryRow("PRAGMA page_count").Scan(&pages); err != nil {
		return false, err
	}
	if err := db.QueryRow("PRAGMA freelist_count").Scan(&free); err != nil {
		return false, err
	}
	if pages == 0 || float64(free)/float64(pages) < vacuumFreeRatio {
		return false, nil
	}
	if _, err := db.Exec("VACUUM"); err != nil {
		return false, err
	}
	// In WAL mode VACUUM writes the whole file through the -wal, which then stays
	// that size; shrink it back (best effort: skipped if a search holds it).
	db.Exec("PRAGMA wal_checkpoint(TRUNCATE)")
	return true, nil
}

// listBackups returns the backup file names in backupDir, oldest first.
func listBackups(backupDir string) []string {
	entries, err := os.ReadDir(backupDir)
	if err != nil {
		return nil
	}
	var names []string
	for _, e := range entries {
		if _, ok := backupTime(e.Name()); ok && !e.IsDir() {
			names = append(names, e.Name())
		}
	}
	sort.Strings(names)
	return names
}

// newestBackupTime is the time of the newest backup not dated in the future. A
// future date means the clock was wrong when it was made; trusting it would stop
// backups until real time caught up.
func newestBackupTime(names []string, now time.Time) (time.Time, bool) {
	for i := len(names) - 1; i >= 0; i-- {
		if t, _ := backupTime(names[i]); !t.After(now) {
			return t, true
		}
	}
	return time.Time{}, false
}

// backupTime parses the time out of a backup file name ("notes-20261018-093000.db").
func backupTime(name string) (time.Time, bool) {
	if !strings.HasPrefix(name, backupPrefix) || !strings.HasSuffix(name, backupSuffix) {
		return time.Time{}, false
	}
	stamp := strings.TrimSuffix(strings.TrimPrefix(name, backupPrefix), backupSuffix)
	t, err := time.Parse(backupTimeLayout, stamp)
	return t, err == nil
}

// pruneBackups keeps the newest keep backups. Future-dated ones (wrong clock)
// count as oldest, so they go first instead of lingering forever. Only called
// after a successful backup, so a good one always remains.
func pruneBackups(backupDir string, keep int, now time.Time) {
	var future, past []string
	for _, name := range listBackups(backupDir) {
		if t, _ := backupTime(name); t.After(now) {
			future = append(future, name)
		} else {
			past = append(past, name)
		}
	}
	oldestFirst := append(future, past...)
	for i := 0; i < len(oldestFirst)-keep; i++ {
		os.Remove(filepath.Join(backupDir, oldestFirst[i]))
	}
}

func removePartials(backupDir string) {
	leftovers, _ := filepath.Glob(filepath.Join(backupDir, backupPrefix+"*"+backupSuffix+partialSuffix))
	for _, p := range leftovers {
		os.Remove(p)
	}
}
