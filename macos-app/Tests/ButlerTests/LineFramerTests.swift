import Foundation
import Testing
@testable import Butler

@Suite struct LineFramerTests {
    private func feed(_ framer: inout LineFramer, _ pieces: [String]) -> [String] {
        pieces.flatMap { framer.append(Data($0.utf8)) }.map { String(decoding: $0, as: UTF8.self) }
    }

    @Test func lineSplitAcrossPieces() {
        var f = LineFramer()
        #expect(feed(&f, [#"{"id":7,"ok""#, #":true,"no"#, #"tes":[]}"#]).isEmpty) // no '\n' yet
        #expect(feed(&f, ["\n"]) == [#"{"id":7,"ok":true,"notes":[]}"#])
    }

    @Test func severalLinesInOnePiece() {
        var f = LineFramer()
        #expect(feed(&f, ["a\nb\nc"]) == ["a", "b"])  // "c" is still incomplete
        #expect(feed(&f, ["\n"]) == ["c"])
    }

    @Test func pieceEndingExactlyOnNewline() {
        var f = LineFramer()
        #expect(feed(&f, ["one\n", "two\n"]) == ["one", "two"])
    }

    @Test func emptyLinesArePreserved() {
        var f = LineFramer()
        #expect(feed(&f, ["\n\nx\n"]) == ["", "", "x"])
    }

    @Test func resetDropsPartialLine() {
        var f = LineFramer()
        _ = feed(&f, ["half a rep"])
        f.reset()
        #expect(feed(&f, ["fresh\n"]) == ["fresh"])
    }

    @Test func largeReplyInPipeSizedPiecesIsFast() {
        // ~21MB line (≈50k notes) in 64KB pieces. The old rescan-everything
        // approach took ~8.6s on this; scanning each byte once takes milliseconds.
        let line = Data(repeating: UInt8(ascii: "x"), count: 21_000_000) + Data([0x0A])
        var f = LineFramer()
        var lines: [Data] = []
        let start = Date()
        var offset = 0
        while offset < line.count {
            let end = min(offset + 65_536, line.count)
            lines += f.append(line.subdata(in: offset..<end))
            offset = end
        }
        let seconds = Date().timeIntervalSince(start)
        #expect(lines.count == 1)
        #expect(lines.first?.count == 21_000_000)
        #expect(seconds < 2, "framing 21MB took \(seconds)s")
    }
}
