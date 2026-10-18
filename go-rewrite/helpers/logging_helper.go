package helpers

import (
	"fmt"
	"os"
	"sync"
	"syscall"
	"time"
)

// Log rotation: once the log reaches MaxLogBytes it becomes <log>.1, older backups
// shift up (.1 → .2 → .3) and the oldest beyond KeepLogBackups is removed — so the
// log never grows past roughly (KeepLogBackups+1) × MaxLogBytes.
const (
	MaxLogBytes    = 1 << 20 // 1MB
	KeepLogBackups = 3

	// After a failed rotation, wait this long before trying again.
	rotationRetryDelay = time.Minute
)

// How often to check that the file at the log path is still the one we have open
// (it may have been deleted or moved by hand). Time-based, so the common path
// costs no extra syscall. A var only so tests can shorten it.
var logRecheckInterval = 5 * time.Second

// The log stays open between calls and its size is tracked in logSize (read once
// when opened, then advanced by each write), so LogIt costs a single write.
var (
	logMu               sync.Mutex
	logStore            string
	logFile             *os.File
	logSize             int64
	logCheckedAt        time.Time
	rotationPausedUntil time.Time
	stderrToLog         bool
)

// SetLogPath points the logger at a file (typically <data dir>/app.log) and opens
// it. Empty disables logging.
func SetLogPath(path string) {
	logMu.Lock()
	defer logMu.Unlock()
	closeLog()
	logStore = path
	if path != "" {
		openLog()
	}
}

// SetStderrToLog makes the log file this process's stderr too (now and after
// every rotation or reopen), so panic traces land in app.log. The app asks for it
// via BUTLER_STDERR_TO_LOG=1; a butler-core run from a terminal keeps its stderr.
func SetStderrToLog(on bool) {
	logMu.Lock()
	defer logMu.Unlock()
	stderrToLog = on
	pointStderrAtLog()
}

func LogIt(varToLog string) {
	logMu.Lock()
	defer logMu.Unlock()
	if logStore == "" {
		return
	}
	now := time.Now()
	if logFile == nil || now.Sub(logCheckedAt) >= logRecheckInterval {
		logCheckedAt = now
		if !logFileStillAtPath() {
			closeLog()
			openLog() // deleted/moved by hand (or never opened): start a fresh file
		}
	}
	if logFile == nil {
		return
	}
	if logSize >= MaxLogBytes && !now.Before(rotationPausedUntil) {
		rotate(now)
	}
	n, _ := logFile.WriteString(fmt.Sprintf("%s %s\n", now.UTC().Format(time.RFC3339), varToLog))
	logSize += int64(n)
}

// rotate moves the full log aside, opens a fresh one, and only then shifts the
// backups — so if the fresh file can't be opened, nothing has been lost: the log
// is put back and rotation is retried later. Caller holds logMu.
func rotate(now time.Time) {
	aside := logStore + ".rotating"
	closeLog()
	if os.Rename(logStore, aside) != nil {
		openLog()
		rotationPausedUntil = now.Add(rotationRetryDelay)
		return
	}
	if !openLog() {
		os.Rename(aside, logStore)
		openLog()
		rotationPausedUntil = now.Add(rotationRetryDelay)
		return
	}
	os.Remove(fmt.Sprintf("%s.%d", logStore, KeepLogBackups))
	for i := KeepLogBackups - 1; i >= 1; i-- {
		os.Rename(fmt.Sprintf("%s.%d", logStore, i), fmt.Sprintf("%s.%d", logStore, i+1))
	}
	os.Rename(aside, logStore+".1")
}

// openLog opens logStore for appending (created if missing, readable only by you —
// it can hold note keys and search queries) and reads its current size.
// Caller holds logMu.
func openLog() bool {
	f, err := os.OpenFile(logStore, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0600)
	if err != nil {
		logFile, logSize = nil, 0
		return false
	}
	f.Chmod(0600) // tighten a log created before logs were private
	logFile, logSize = f, 0
	if info, err := f.Stat(); err == nil {
		logSize = info.Size()
	}
	pointStderrAtLog()
	return true
}

// logFileStillAtPath reports whether the open file is the one at logStore.
// Caller holds logMu.
func logFileStillAtPath() bool {
	if logFile == nil {
		return false
	}
	atPath, err := os.Stat(logStore)
	if err != nil {
		return false
	}
	open, err := logFile.Stat()
	return err == nil && os.SameFile(atPath, open)
}

// pointStderrAtLog makes fd 2 the open log when stderrToLog is set. Caller holds logMu.
func pointStderrAtLog() {
	if stderrToLog && logFile != nil {
		syscall.Dup2(int(logFile.Fd()), int(os.Stderr.Fd()))
	}
}

// closeLog closes the open log, if any. Caller holds logMu.
func closeLog() {
	if logFile != nil {
		logFile.Close()
		logFile = nil
	}
}

func Error_happened(err error) bool {
	if err != nil {
		LogIt(fmt.Sprintf("ERROR: %s", err))
		return true
	}
	return false
}
