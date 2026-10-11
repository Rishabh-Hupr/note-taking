import Foundation

/// Splits a byte stream into newline-terminated lines. The pipe delivers a reply
/// in ~64KB pieces, so a line usually spans many `append` calls.
///
/// It remembers how far it has already searched, so each byte is scanned for
/// '\n' exactly once. The old approach rescanned the whole buffer on every piece
/// — quadratic: a 42MB reply (100k notes) took ~34s and blew the 5s timeout.
struct LineFramer {
    private var buffer = Data()
    /// Leading bytes of `buffer` already known to contain no '\n'.
    private var scanned = 0

    /// Add a piece; returns any lines it completed (without the '\n').
    mutating func append(_ piece: Data) -> [Data] {
        buffer.append(piece)
        var lines: [Data] = []
        var lineStart = buffer.startIndex
        var searchFrom = buffer.startIndex + scanned
        while let newline = buffer[searchFrom...].firstIndex(of: 0x0A) {
            lines.append(buffer.subdata(in: lineStart..<newline))
            lineStart = newline + 1
            searchFrom = lineStart
        }
        // Drop completed lines in one go (not once per line), keep the partial tail.
        if lineStart > buffer.startIndex {
            buffer.removeSubrange(buffer.startIndex..<lineStart)
        }
        scanned = buffer.count
        return lines
    }

    /// Discard a partial line (e.g. the process died mid-reply).
    mutating func reset() {
        buffer.removeAll()
        scanned = 0
    }
}
