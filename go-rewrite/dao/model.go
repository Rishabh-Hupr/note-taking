package dao

// Note is the shared data contract between the Go core and the Swift frontend.
// The JSON tags define the wire format; the Swift side mirrors this as a Codable.
type Note struct {
	Key       string  `json:"key"`
	Value     string  `json:"value"`
	CreatedAt string  `json:"created_at"`
	UpdatedAt string  `json:"updated_at"`
	Rank      float64 `json:"rank"`
}
