package main

import (
	"Go-Butler/helpers"
	"Go-Butler/processor"
	"bufio"
	"bytes"
	"database/sql"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
)

// dataDir resolves the Butler data directory: $BUTLER_DATA_DIR, else ~/.butler.
func dataDir() (string, error) {
	if d := os.Getenv("BUTLER_DATA_DIR"); d != "" {
		return d, nil
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(home, ".butler"), nil
}

func main() {
	dir, err := dataDir()
	if err != nil {
		helpers.LogIt(fmt.Sprintf("cannot resolve data dir: %v\n", err))
		os.Exit(1)
	}
	helpers.SetLogPath(filepath.Join(dir, "app.log"))

	notesDB, err := NewNotesDatabase(dir)
	if err != nil {
		helpers.LogIt(fmt.Sprintf("cannot open database: %v\n", err))
		os.Exit(1)
	}
	defer notesDB.Close()
	db := notesDB.DB()

	// bufio.Reader (not Scanner) so an arbitrarily long request line grows the
	// buffer instead of erroring out and killing the sidecar.
	in := bufio.NewReader(os.Stdin)
	out := bufio.NewWriter(os.Stdout)

	for {
		line, err := in.ReadBytes('\n')

		if line = bytes.TrimSpace(line); len(line) > 0 {
			serveLine(db, out, line)
		}

		if err != nil {
			// io.EOF = stdin closed (frontend exited) — normal shutdown.
			if err != io.EOF {
				helpers.LogIt(fmt.Sprintf("stdin read error: %v", err))
			}
			break
		}
	}
}

// serveLine handles exactly one request line. Its deferred recover is the last
// line of defense: SafeHandler already guards the handler, but WriteResponse and
// JSON decoding run here too, so a panic anywhere in the cycle is caught, logged
// with a timestamp and the offending request
func serveLine(db *sql.DB, out *bufio.Writer, line []byte) {
	defer func() {
		if r := recover(); r != nil {
			helpers.LogIt(fmt.Sprintf("PANIC handling request %q: %v", line, r))
			// Best-effort reply so the frontend fails fast instead of timing out.
			processor.WriteResponse(out, processor.Response{ID: bestEffortID(line), Error: fmt.Sprintf("internal error: %v", r)})
		}
	}()

	var req processor.Request
	if uerr := json.Unmarshal(line, &req); uerr != nil {
		helpers.LogIt(fmt.Sprintf("bad request: %v, for request: %s", uerr, line))
		processor.WriteResponse(out, processor.Response{ID: bestEffortID(line), Error: fmt.Sprintf("bad request: %v", uerr)})
		return
	}
	processor.WriteResponse(out, processor.SafeHandler(db, req))
}

// bestEffortID tries to recover the request id from a line that failed to parse
// as a full request, so the frontend can still correlate the error response.
func bestEffortID(line []byte) int {
	var probe struct {
		ID int `json:"id"`
	}
	_ = json.Unmarshal(line, &probe)
	return probe.ID
}
