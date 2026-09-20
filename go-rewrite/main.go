package main

import (
	"Go-Butler/dao"
	"Go-Butler/utils"
	"bufio"
	"bytes"
	"database/sql"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
)

// request is one JSON line read from stdin.
type request struct {
	ID    int    `json:"id"`
	Cmd   string `json:"cmd"`
	Key   string `json:"key,omitempty"`
	Value string `json:"value,omitempty"`
	Query string `json:"query,omitempty"`
}

// response is one JSON line written to stdout.
type response struct {
	ID    int        `json:"id"`
	OK    bool       `json:"ok"`
	Notes []dao.Note `json:"notes,omitempty"`
	Error string     `json:"error,omitempty"`
}

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
		fmt.Fprintf(os.Stderr, "cannot resolve data dir: %v\n", err)
		os.Exit(1)
	}
	utils.SetLogPath(filepath.Join(dir, "app.log"))

	notesDB, err := NewNotesDatabase(dir)
	if err != nil {
		fmt.Fprintf(os.Stderr, "cannot open database: %v\n", err)
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
			var req request
			if uerr := json.Unmarshal(line, &req); uerr != nil {
				writeResp(out, response{ID: bestEffortID(line), Error: fmt.Sprintf("bad request: %v", uerr)})
			} else {
				writeResp(out, safeHandle(db, req))
			}
		}

		if err != nil {
			// io.EOF = stdin closed (frontend exited) — normal shutdown.
			if err != io.EOF {
				utils.LogIt(fmt.Sprintf("stdin read error: %v", err))
			}
			break
		}
	}
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

// safeHandle runs handle but converts a panic on any single request into an
// error response, so one bad request can't crash the whole sidecar.
func safeHandle(db *sql.DB, req request) (resp response) {
	defer func() {
		if r := recover(); r != nil {
			utils.LogIt(fmt.Sprintf("recovered from panic on cmd %q: %v", req.Cmd, r))
			resp = response{ID: req.ID, Error: fmt.Sprintf("internal error: %v", r)}
		}
	}()
	return handle(db, req)
}

// handle dispatches one request. Adding a new op is a new case here.
func handle(db *sql.DB, req request) response {
	resp := response{ID: req.ID}

	switch req.Cmd {
	case "ping":
		resp.OK = true

	case "put":
		if req.Key == "" || req.Value == "" {
			resp.Error = "put requires both key and value"
			return resp
		}
		if err := dao.PutNote(db, dao.Note{Key: req.Key, Value: req.Value}); err != nil {
			resp.Error = err.Error()
			return resp
		}
		resp.OK = true

	case "fetch":
		notes, err := dao.FetchNote(db, req.Query)
		if err != nil {
			resp.Error = err.Error()
			return resp
		}
		resp.OK = true
		resp.Notes = notes

	case "list":
		notes, err := dao.ShowDB(db)
		if err != nil {
			resp.Error = err.Error()
			return resp
		}
		resp.OK = true
		resp.Notes = notes

	default:
		resp.Error = fmt.Sprintf("unknown cmd: %q", req.Cmd)
	}

	return resp
}

func writeResp(out *bufio.Writer, resp response) {
	b, err := json.Marshal(resp)
	if err != nil {
		// Never leave the frontend without a line for this id (it would hang
		// waiting): emit a minimal hand-built error response instead.
		utils.LogIt(fmt.Sprintf("marshal error for id %d: %v", resp.ID, err))
		b = []byte(fmt.Sprintf(`{"id":%d,"error":"response encoding failed"}`, resp.ID))
	}
	out.Write(b)
	out.WriteByte('\n')
	out.Flush()
}
