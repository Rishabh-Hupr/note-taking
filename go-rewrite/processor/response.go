package processor

import (
	"Go-Butler/helpers"
	"bufio"
	"encoding/json"
	"fmt"
)

func WriteResponse(out *bufio.Writer, resp Response) {
	b, err := json.Marshal(resp)
	if err != nil {
		// Never leave the frontend without a line for this id (it would hang
		// waiting): emit a minimal hand-built error response instead.
		helpers.LogIt(fmt.Sprintf("marshal error for id %d: %v", resp.ID, err))
		b = []byte(fmt.Sprintf(`{"id":%d,"error":"response encoding failed"}`, resp.ID))
	}
	out.Write(b)
	out.WriteByte('\n')
	out.Flush()
}
