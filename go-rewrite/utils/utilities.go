package utils

import (
	"fmt"
	"os"
	"time"
)

// logStore is the log file path. Empty means logging is disabled; call
// SetLogPath at startup to enable it.
var logStore string

// SetLogPath points the logger at a file (typically <data dir>/app.log).
func SetLogPath(path string) {
	logStore = path
}

func LogIt(varToLog string) {
	if logStore == "" {
		return
	}

	// Open file in append mode, create if not exists, with write-only permissions
	f, err := os.OpenFile(logStore, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	if err != nil {
		return
	}
	defer f.Close()

	// Get current UTC timestamp
	timestamp := time.Now().UTC().Format(time.RFC3339) // Example: 2025-06-15T14:00:00Z
	logLine := fmt.Sprintf("%s %s\n", timestamp, varToLog)

	f.WriteString(logLine)
}

func Error_happened(err error) bool {
	if err != nil {
		LogIt(fmt.Sprintf("ERROR: %s", err))
		return true
	}
	return false
}
