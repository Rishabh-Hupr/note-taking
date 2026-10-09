import Foundation
import Testing
@testable import Butler

// Wire-contract tests: these JSON shapes must match the Go sidecar
// (go-rewrite/dao/note_model.go, go-rewrite/processor/request_model.go).
@Suite struct ModelsTests {
    @Test func decodesNoteFromGoJSON() throws {
        let json = #"""
        {"id":7,"key":"wifi","value":"hunter2","created_at":"2026-09-20T15:49:45Z",
         "updated_at":"2026-09-21T10:00:00Z","rank":-1.5}
        """#
        let note = try JSONDecoder().decode(Note.self, from: Data(json.utf8))
        #expect(note == Note(id: 7, key: "wifi", value: "hunter2",
                             createdAt: "2026-09-20T15:49:45Z",
                             updatedAt: "2026-09-21T10:00:00Z", rank: -1.5))
    }

    @Test func decodesSuccessResponseWithNotes() throws {
        let json = #"""
        {"id":3,"ok":true,"notes":[{"id":1,"key":"k","value":"v",
          "created_at":"a","updated_at":"b","rank":0}]}
        """#
        let resp = try JSONDecoder().decode(SidecarResponse.self, from: Data(json.utf8))
        #expect(resp.id == 3)
        #expect(resp.ok)
        #expect(resp.notes?.count == 1)
        #expect(resp.error == nil)
    }

    @Test func decodesErrorResponseWithoutNotes() throws {
        // Go omits "notes" (omitempty) on errors and on put/ping/delete.
        let json = #"{"id":9,"ok":false,"error":"unknown cmd: \"x\""}"#
        let resp = try JSONDecoder().decode(SidecarResponse.self, from: Data(json.utf8))
        #expect(!resp.ok)
        #expect(resp.notes == nil)
        #expect(resp.error == #"unknown cmd: "x""#)
    }

    @Test func encodesDeleteRequestWithNoteIDKey() throws {
        let req = SidecarRequest(id: 4, cmd: "delete", noteID: 12)
        let obj = try jsonObject(req)
        #expect(obj["note_id"] as? Int == 12)
        #expect(obj["noteID"] == nil)
    }

    @Test func omitsUnsetOptionalFields() throws {
        // Go's handler treats missing fields as empty; they must not be sent as null.
        let obj = try jsonObject(SidecarRequest(id: 1, cmd: "ping"))
        #expect(Set(obj.keys) == ["id", "cmd"])
    }

    @Test func encodesPutRequest() throws {
        let obj = try jsonObject(SidecarRequest(id: 2, cmd: "put", key: "k", value: "line1\nline2"))
        #expect(obj["key"] as? String == "k")
        #expect(obj["value"] as? String == "line1\nline2")
        #expect(obj["query"] == nil)
    }

    private func jsonObject(_ req: SidecarRequest) throws -> [String: Any] {
        let data = try JSONEncoder().encode(req)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
