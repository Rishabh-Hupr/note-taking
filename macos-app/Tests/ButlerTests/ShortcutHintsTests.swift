import AppKit
import Testing
@testable import Butler

@Suite struct ShortcutHintsTests {
    // Every hint's keys and action appear, in order, each in the hint's colour.
    @Test func everyHintShowsInItsColour() {
        for hints in [ShortcutHints.search, ShortcutHints.put] {
            let text = ShortcutHints.text(hints)
            let plain = text.string as NSString
            var searchFrom = 0
            for hint in hints {
                let range = plain.range(of: hint.keys + " " + hint.action,
                                        range: NSRange(location: searchFrom, length: plain.length - searchFrom))
                #expect(range.location != NSNotFound, "'\(hint.keys) \(hint.action)' missing or out of order")
                guard range.location != NSNotFound else { continue }
                searchFrom = NSMaxRange(range)
                var effective = NSRange()
                let color = text.attribute(.foregroundColor, at: range.location, effectiveRange: &effective) as? NSColor
                #expect(color == hint.color && NSMaxRange(effective) >= NSMaxRange(range),
                        "'\(hint.action)' isn't all in its colour")
            }
        }
    }
}
