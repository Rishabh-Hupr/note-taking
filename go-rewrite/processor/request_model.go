package processor

import "Go-Butler/dao"

// request is one JSON line read from stdin.
type Request struct {
	ID     int    `json:"id"`  // request-correlation id, echoed back in the response
	Cmd    string `json:"cmd"`
	Key    string `json:"key,omitempty"`
	Value  string `json:"value,omitempty"`
	Query  string `json:"query,omitempty"`
	NoteID int    `json:"note_id,omitempty"` // note primary key, used by delete
}

// response is one JSON line written to stdout.
type Response struct {
	ID    int        `json:"id"`
	OK    bool       `json:"ok"`
	Notes []dao.Note `json:"notes,omitempty"`
	Error string     `json:"error,omitempty"`
}
