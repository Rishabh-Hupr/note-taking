package processor

import (
	"Go-Butler/dao"
	"Go-Butler/dao/operations"
	"Go-Butler/helpers"
	"database/sql"
	"fmt"
)

// safeHandle runs handle but converts a panic on any single request into an
// error response, so one bad request can't crash the whole sidecar.
func SafeHandler(db *sql.DB, req Request) (resp Response) {
	defer func() {
		if r := recover(); r != nil {
			helpers.LogIt(fmt.Sprintf("recovered from panic on cmd %q: %v", req.Cmd, r))
			resp = Response{ID: req.ID, Error: fmt.Sprintf("internal error: %v", r)}
		}
	}()
	return handler(db, req)
}

// handle dispatches one request. Adding a new op is a new case here.
func handler(db *sql.DB, req Request) Response {
	resp := Response{ID: req.ID}

	switch req.Cmd {
	case "ping":
		resp.OK = true

	case "put":
		if req.Key == "" || req.Value == "" {
			resp.Error = "put requires both key and value"
			return resp
		}
		if err := operations.PutNote(db, dao.Note{Key: req.Key, Value: req.Value}); err != nil {
			resp.Error = err.Error()
			return resp
		}
		resp.OK = true

	case "fetch":
		notes, err := operations.FetchNote(db, req.Query)
		if err != nil {
			resp.Error = err.Error()
			return resp
		}
		resp.OK = true
		resp.Notes = notes

	case "list":
		notes, err := operations.ShowDB(db)
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
