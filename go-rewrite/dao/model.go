package dao

// Note is the shared data contract between the Go core and the Swift frontend.
// The JSON tags define the wire format; the Swift side mirrors this as a Codable.
//
// CreatedAt/UpdatedAt are strings, not time.Time: go-sqlite3 auto-parses the
// TIMESTAMP columns into time.Time and database/sql renders them back to RFC3339
// (e.g. "2026-09-20T15:49:45Z") when scanned into a string. We keep the string
// form as-is for the wire; the frontend can parse it if it needs a date type.
type Note struct {
	Key       string  `json:"key"`
	Value     string  `json:"value"`
	CreatedAt string  `json:"created_at"`
	UpdatedAt string  `json:"updated_at"`
	Rank      float64 `json:"rank"`
}
