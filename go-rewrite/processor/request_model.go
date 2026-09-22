package processor

import "Go-Butler/dao"

// request is one JSON line read from stdin.
type Request struct {
	ID    int    `json:"id"`
	Cmd   string `json:"cmd"`
	Key   string `json:"key,omitempty"`
	Value string `json:"value,omitempty"`
	Query string `json:"query,omitempty"`
}

// response is one JSON line written to stdout.
type Response struct {
	ID    int        `json:"id"`
	OK    bool       `json:"ok"`
	Notes []dao.Note `json:"notes,omitempty"`
	Error string     `json:"error,omitempty"`
}
