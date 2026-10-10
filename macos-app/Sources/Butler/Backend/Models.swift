import Foundation

// Note mirrors the Go dao.Note wire contract exactly (JSON keys must match).
struct Note: Codable, Equatable {
    let id: Int
    let key: String
    let value: String
    let createdAt: String
    let updatedAt: String
    let rank: Double

    enum CodingKeys: String, CodingKey {
        case id, key, value, rank
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// SidecarRequest is one line sent to butler-core. Only the fields relevant to a
// given cmd are populated; the rest stay nil and are omitted from the JSON.
struct SidecarRequest: Encodable {
    let id: Int
    let cmd: String
    var key: String?
    var value: String?
    var query: String?
    var noteID: Int?

    enum CodingKeys: String, CodingKey {
        case id, cmd, key, value, query
        case noteID = "note_id"
    }
}

// SidecarResponse is one line read back from butler-core.
struct SidecarResponse: Decodable {
    let id: Int
    let ok: Bool
    let notes: [Note]?
    let error: String?
}
