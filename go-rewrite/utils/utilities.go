package utils

import (
	"errors"
	"fmt"
	"os"
	"time"

	"github.com/ncruces/zenity"
)

const logStore string = "/Users/machupr/note-taking/go-rewrite/app.log"

func LogIt(varToLog string) {

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
		if errors.Is(err, zenity.ErrCanceled) {
			return false // User canceled the operation, not an error
		}
		framedError := fmt.Sprintf("‼️ ERROR: %s", err)
		LogIt(framedError)
		return true
	}
	return false
}
