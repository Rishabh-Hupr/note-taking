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
)

// The log stays open between calls and its size is tracked in logSize (read once
// when opened, then advanced by each write), so LogIt costs a single write — no
// open, stat or close per line. Output written to the file by others (the app
// hands this process app.log as stderr, for panic traces) isn't counted until the
// next reopen, which re-reads the real size.
var (
	logMu            sync.Mutex
	logStore         string
	logFile          *os.File
	logSize          int64
	stderrFollowsLog bool
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

// SetStderrFollowsLog makes stderr track the log across rotations. The app hands
// this process app.log as its stderr; after a rotation that fd would still point at
// the renamed file, so the next panic would land in app.log.1 — or a deleted file.
// Off by default (tests).
func SetStderrFollowsLog(on bool) {
	logMu.Lock()
	defer logMu.Unlock()
	stderrFollowsLog = on
}

func LogIt(varToLog string) {
	logMu.Lock()
	defer logMu.Unlock()
	if logFile == nil {
		return
	}
	if logSize >= MaxLogBytes {
		closeLog()
		rotateFiles(logStore, KeepLogBackups)
		if !openLog() {
			return
		}
		if stderrFollowsLog {
			syscall.Dup2(int(logFile.Fd()), int(os.Stderr.Fd()))
		}
	}
	timestamp := time.Now().UTC().Format(time.RFC3339) // e.g. 2025-06-15T14:00:00Z
	n, _ := logFile.WriteString(fmt.Sprintf("%s %s\n", timestamp, varToLog))
	logSize += int64(n)
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
	return true
}

// closeLog closes the open log, if any. Caller holds logMu.
func closeLog() {
	if logFile != nil {
		logFile.Close()
		logFile = nil
	}
}

// rotateFiles shifts path → path.1 → … → path.keep, dropping the oldest.
func rotateFiles(path string, keep int) {
	os.Remove(fmt.Sprintf("%s.%d", path, keep))
	for i := keep - 1; i >= 1; i-- {
		os.Rename(fmt.Sprintf("%s.%d", path, i), fmt.Sprintf("%s.%d", path, i+1))
	}
	os.Rename(path, path+".1")
}

func Error_happened(err error) bool {
	if err != nil {
		LogIt(fmt.Sprintf("ERROR: %s", err))
		return true
	}
	return false
}
