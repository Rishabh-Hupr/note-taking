package main

import (
	"Go-Butler/dao"
	"Go-Butler/utils"
	"bufio"
	"database/sql"
	"encoding/json"
	"fmt"
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
	defer notesDB.db.Close()
	db := notesDB.DB()

	in := bufio.NewScanner(os.Stdin)
	in.Buffer(make([]byte, 0, 1024*1024), 1024*1024) // allow long note values
	out := bufio.NewWriter(os.Stdout)

	for in.Scan() {
		line := in.Bytes()
		if len(line) == 0 {
			continue
		}

		var req request
		if err := json.Unmarshal(line, &req); err != nil {
			writeResp(out, response{OK: false, Error: fmt.Sprintf("bad request: %v", err)})
			continue
		}

		writeResp(out, safeHandle(db, req))
	}

	// stdin closed (frontend exited) or scan error — shut down.
	if err := in.Err(); err != nil {
		utils.LogIt(fmt.Sprintf("stdin scan error: %v", err))
	}
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
		utils.LogIt(fmt.Sprintf("marshal error: %v", err))
		return
	}
	out.Write(b)
	out.WriteByte('\n')
	out.Flush()
}
