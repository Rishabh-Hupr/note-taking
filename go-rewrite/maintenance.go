//go:build sqlite_fts5
// +build sqlite_fts5

package main

import (
	"Go-Butler/helpers"
	"database/sql"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

// Database upkeep, run every maintenanceInterval from the main loop (between
// requests, so it never races a put or delete):
//  1. FTS5 optimize — merges the search index's segments into one.
//  2. VACUUM, only when free pages are at least vacuumFreeRatio of the file.
//  3. A backup into <data dir>/backups/ via VACUUM INTO — a complete, standalone
//     copy (notes, search index and triggers), checked before it is kept. The
//     newest backupsToKeep are kept. Restoring one is a file copy: see README.
const (
	maintenanceInterval   = 48 * time.Hour
	backupsToKeep         = 7 // with a 2-day interval: two weeks of history
	vacuumFreeRatio       = 0.2
	firstMaintenanceDelay = 30 * time.Second // after launch, so it never slows startup
	maintenanceCheckEvery = time.Hour        // the backend can run for days

	backupDirName    = "backups"
	backupPrefix     = "notes-"
	backupSuffix     = ".db"
	backupTimeLayout = "20060102-150405" // sorts chronologically as text
)

// maintainIfDue runs the upkeep when the newest backup is older than
// maintenanceInterval (or there is none). Cheap when not due: one directory read.
func maintainIfDue(db *sql.DB, dir string, now time.Time) {
	backupDir := filepath.Join(dir, backupDirName)
	backups := listBackups(backupDir)
	if len(backups) > 0 {
		if last, ok := backupTime(backups[len(backups)-1]); ok && now.Sub(last) < maintenanceInterval {
			return
		}
	}
	start := time.Now()
	if err := optimizeFTS(db); err != nil {
		helpers.LogIt(fmt.Sprintf("maintenance: FTS optimize failed: %v", err))
	}
	if vacuumed, err := vacuumIfFragmented(db); err != nil {
		helpers.LogIt(fmt.Sprintf("maintenance: VACUUM failed: %v", err))
	} else if vacuumed {
		helpers.LogIt("maintenance: VACUUM reclaimed free pages")
	}
	path, err := backup(db, backupDir, now)
	if err != nil {
		helpers.LogIt(fmt.Sprintf("maintenance: backup failed: %v", err))
	} else {
		pruneBackups(backupDir, backupsToKeep)
		helpers.LogIt(fmt.Sprintf("maintenance: backed up to %s", filepath.Base(path)))
	}
	helpers.LogIt(fmt.Sprintf("maintenance: done in %dms", time.Since(start).Milliseconds()))
}

func optimizeFTS(db *sql.DB) error {
	_, err := db.Exec("INSERT INTO notes_fts(notes_fts) VALUES('optimize')")
	return err
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
	_, err := db.Exec("VACUUM")
	return err == nil, err
}

// backup writes a snapshot to backupDir and checks it (SQLite and FTS5 integrity)
// before giving it its final name, so a listed backup is always a good one.
func backup(db *sql.DB, backupDir string, now time.Time) (string, error) {
	if err := os.MkdirAll(backupDir, 0700); err != nil {
		return "", err
	}
	final := filepath.Join(backupDir, backupPrefix+now.Format(backupTimeLayout)+backupSuffix)
	partial := final + ".partial"
	os.Remove(partial) // VACUUM INTO refuses to overwrite a leftover from a crash
	if _, err := db.Exec("VACUUM INTO ?", partial); err != nil {
		os.Remove(partial)
		return "", err
	}
	if err := checkBackup(partial); err != nil {
		os.Remove(partial)
		return "", fmt.Errorf("backup failed its check: %w", err)
	}
	os.Chmod(partial, 0600) // notes are private
	if err := os.Rename(partial, final); err != nil {
		os.Remove(partial)
		return "", err
	}
	return final, nil
}

func checkBackup(path string) error {
	b, err := sql.Open("sqlite3", path)
	if err != nil {
		return err
	}
	defer b.Close()
	var result string
	if err := b.QueryRow("PRAGMA quick_check").Scan(&result); err != nil {
		return err
	}
	if result != "ok" {
		return fmt.Errorf("quick_check: %s", result)
	}
	// Errors if the search index doesn't match the notes.
	_, err = b.Exec("INSERT INTO notes_fts(notes_fts, rank) VALUES('integrity-check', 1)")
	return err
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

// backupTime parses the time out of a backup file name ("notes-20261018-093000.db").
func backupTime(name string) (time.Time, bool) {
	if !strings.HasPrefix(name, backupPrefix) || !strings.HasSuffix(name, backupSuffix) {
		return time.Time{}, false
	}
	stamp := strings.TrimSuffix(strings.TrimPrefix(name, backupPrefix), backupSuffix)
	t, err := time.ParseInLocation(backupTimeLayout, stamp, time.Local)
	return t, err == nil
}

// pruneBackups deletes all but the newest keep backups.
func pruneBackups(backupDir string, keep int) {
	backups := listBackups(backupDir)
	for i := 0; i < len(backups)-keep; i++ {
		os.Remove(filepath.Join(backupDir, backups[i]))
	}
}
