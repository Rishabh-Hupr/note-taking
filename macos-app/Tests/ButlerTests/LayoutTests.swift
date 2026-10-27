import AppKit
import Testing
@testable import Butler

@Suite struct LayoutTests {
    let font = NSFont.systemFont(ofSize: 12)
    var lineHeight: CGFloat { NSLayoutManager().defaultLineHeight(for: font) }

    private func lines(_ n: Int) -> String {
        (1...n).map { "line \($0)" }.joined(separator: "\n")
    }

    // MARK: Text measurement

    @Test func textHeightIsDeterministic() {
        let text = String(repeating: "a fairly long note body that wraps. ", count: 80)
        let first = OverlayLayout.textHeight(text, width: 388, font: font)
        for _ in 0..<5 {
            #expect(OverlayLayout.textHeight(text, width: 388, font: font) == first)
        }
    }

    @Test func textHeightGrowsWithLineCount() {
        let three = OverlayLayout.textHeight(lines(3), width: 388, font: font)
        let ten = OverlayLayout.textHeight(lines(10), width: 388, font: font)
        #expect(ten > three)
    }

    @Test func narrowerWidthWrapsTaller() {
        let text = String(repeating: "word ", count: 200)
        #expect(OverlayLayout.textHeight(text, width: 150, font: font)
                > OverlayLayout.textHeight(text, width: 400, font: font))
    }

    // A long, structured note (headings, indented lines, no-break spaces), the
    // shape of the real 6KB note that froze the preview.
    private var longStructuredNote: String {
        (1...116).map { i in
            i % 7 == 0 ? "SECTION \(i)\n--------"
                : "  \u{a0}\u{a0}step \(i): ALB authenticate-oidc → lambda (regional_stack.ts), cookie=AWSELB \(i)"
        }.joined(separator: "\n")
    }

    // Same heights as NSString.boundingRect, which the views were sized by before.
    @Test func textHeightMatchesBoundingRect() {
        let texts = [lines(1), lines(9), String(repeating: "word ", count: 300),
                     "unbroken" + String(repeating: "x", count: 400), "emoji 📒✅ and ünïcödé\n\nblank above",
                     longStructuredNote]
        for text in texts {
            for width in [150, 300, 374, 388, 600] as [CGFloat] {
                let expected = ceil((text as NSString).boundingRect(
                    with: NSSize(width: width, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: [.font: font]).height)
                #expect(OverlayLayout.textHeight(text, width: width, font: font) == expected,
                        "width \(width), text \(text.prefix(20))")
            }
        }
    }

    // The one difference from boundingRect: "" (empty notes can't be saved).
    @Test func emptyTextIsTheOneDifference() {
        let bounding = ceil(("" as NSString).boundingRect(
            with: NSSize(width: 300, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font]).height)
        #expect(OverlayLayout.textHeight("", width: 300, font: font) == bounding - 1)
    }

    // Each selection measures its note several times on the main thread, so this
    // must stay cheap. Timed against boundingRect (what it replaced, ~50× slower
    // on this text) in the same run, best of 5 each, so other tests running in
    // parallel slow both alike instead of failing a fixed time limit.
    @Test func textHeightIsFastForLongNotes() {
        let text = longStructuredNote
        func bestMs(_ measure: () -> Void) -> Double {
            (0..<5).map { _ in
                let start = DispatchTime.now().uptimeNanoseconds
                measure()
                return Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6
            }.min()!
        }
        let textKit = bestMs { _ = OverlayLayout.textHeight(text, width: 374, font: font) }
        let boundingRect = bestMs {
            _ = (text as NSString).boundingRect(
                with: NSSize(width: 374, height: CGFloat.greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font])
        }
        #expect(textKit * 5 < boundingRect, "TextKit \(textKit)ms vs boundingRect \(boundingRect)ms")
    }

    // MARK: Measuring only the start of a note

    private func maxChars(width: CGFloat, font f: NSFont) -> Int {
        OverlayLayout.maxCharsPerLine(width: width, narrowestAdvance: OverlayLayout.narrowestAdvance(f))
    }

    @Test func leadingExcerptKeepsShortNotesWhole() {
        #expect(OverlayLayout.leadingExcerpt(lines(8), lines: 8, maxCharsPerLine: 300) == lines(8)[...])
        #expect(OverlayLayout.leadingExcerpt(lines(9), lines: 8, maxCharsPerLine: 300) == lines(9)[...])
    }

    @Test func leadingExcerptStopsOneLinePastTheLimit() {
        let cut = OverlayLayout.leadingExcerpt(longStructuredNote, lines: 8, maxCharsPerLine: 300)
        #expect(longStructuredNote.hasPrefix(cut))
        #expect(cut.split(separator: "\n", omittingEmptySubsequences: false).count == 9)
    }

    // Windows (\r\n), old-Mac (\r) and Unicode line breaks count as lines too:
    // TextKit wraps on all of them.
    @Test(arguments: ["\r\n", "\r", "\u{2028}", "\u{2029}", "\u{85}", "\u{0B}", "\u{0C}"])
    func leadingExcerptCountsEveryLineBreak(separator: String) {
        let text = (1...30).map { "line \($0)" }.joined(separator: separator)
        let cut = OverlayLayout.leadingExcerpt(text, lines: 8, maxCharsPerLine: 300)
        #expect(cut == (1...9).map { "line \($0)" }.joined(separator: separator)[...])
    }

    // The core guarantee: measuring only the start gives the same answers a
    // capped view needs. Exact height when the note fits; over the limit when it
    // doesn't. Checked across note shapes, widths and font sizes.
    @Test(arguments: [300, 592, 1200, 2560] as [CGFloat])
    func leadingTextHeightAnswersLikeTheWholeNote(width: CGFloat) {
        let texts = [lines(1), lines(8), lines(9), lines(60), longStructuredNote,
                     String(repeating: "word ", count: 5000), String(repeating: "i", count: 20000),
                     String(repeating: "l\u{27}.", count: 7000), "a\r\nb\r\n" + String(repeating: "x ", count: 8000),
                     String(repeating: "\n", count: 3) + String(repeating: "x ", count: 8000),
                     String(repeating: "漢字かな ", count: 3000)]
        for size in [9, 12, 16] as [CGFloat] {
            let f = NSFont.systemFont(ofSize: size)
            let lh = NSLayoutManager().defaultLineHeight(for: f)
            for limit in [8, 50] {
                for text in texts {
                    let whole = OverlayLayout.textHeight(text, width: width, font: f)
                    let lead = OverlayLayout.leadingTextHeight(text, lines: limit, width: width, font: f,
                                                               maxCharsPerLine: maxChars(width: width, font: f))
                    let fits = !OverlayLayout.exceedsLines(textHeight: whole, lineHeight: lh, limit: limit)
                    let label = "\(size)pt, \(width)pt, \(limit) lines, \(text.prefix(12).debugDescription)"
                    #expect(OverlayLayout.exceedsLines(textHeight: lead, lineHeight: lh, limit: limit) == !fits, "\(label)")
                    if fits { #expect(lead == whole, "\(label)") }
                }
            }
        }
    }

    // The per-line cap really is more than a line holds in the narrowest character.
    @Test(arguments: [300, 592, 1200, 2560] as [CGFloat])
    func maxCharsPerLineOverflowsOneLine(width: CGFloat) {
        for size in [9, 12, 16] as [CGFloat] {
            let f = NSFont.systemFont(ofSize: size)
            let n = maxChars(width: width, font: f)
            for char in ["i", "l", "'", ".", "|"] {
                let line = String(repeating: char, count: n)
                #expect(OverlayLayout.textHeight(line, width: width, font: f)
                        > NSLayoutManager().defaultLineHeight(for: f) * 1.5,
                        "\(n) × \(char) fits one \(width)pt line at \(size)pt")
            }
        }
    }

    // Landing on a note must cost the same however long it is. Exact check:
    // a 1.5MB note is measured from exactly the same start as a 6KB one.
    @Test func leadingTextHeightMeasuresOnlyTheStart() {
        let small = longStructuredNote
        let huge = String(repeating: small + "\n", count: 250)
        let chars = maxChars(width: 374, font: font)
        let start = OverlayLayout.leadingExcerpt(huge, lines: 50, maxCharsPerLine: chars)
        #expect(start == OverlayLayout.leadingExcerpt(small, lines: 50, maxCharsPerLine: chars))
        #expect(start.count <= chars * 52)
        #expect(OverlayLayout.leadingTextHeight(huge, lines: 50, width: 374, font: font, maxCharsPerLine: chars)
                == OverlayLayout.textHeight(String(start), width: 374, font: font))
    }

    // Coarse timing on top: measuring the whole 1.5MB note took over 600ms, the
    // start about 1.5ms. Other tests running in parallel add up to ~20ms of
    // noise either way, so this only flags the whole-note kind of regression.
    @Test func leadingTextHeightStaysFastOnAHugeNote() {
        let huge = String(repeating: longStructuredNote + "\n", count: 250)
        let chars = maxChars(width: 374, font: font)
        let best = (0..<5).map { _ in
            let start = DispatchTime.now().uptimeNanoseconds
            _ = OverlayLayout.leadingTextHeight(huge, lines: 50, width: 374, font: font, maxCharsPerLine: chars)
            return Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6
        }.min()!
        #expect(best < 100, "1.5MB note took \(best)ms")
    }

    @Test func oneLineSummaryJoinsLinesAndStaysShort() {
        let summary = OverlayLayout.oneLineSummary("a\r\nb\nc\u{2028}d" + String(repeating: "x", count: 5000),
                                                   maxCharsPerLine: 100)
        #expect(summary.hasPrefix("a b c d"))
        let hasLineBreak = summary.contains { $0.isNewline }
        #expect(!hasLineBreak)
        #expect(summary.count == 200)
    }

    // MARK: Inline 8-line threshold

    @Test func eightLinesStayInline() {
        let h = OverlayLayout.textHeight(lines(8), width: 600, font: font)
        #expect(!OverlayLayout.exceedsLines(textHeight: h, lineHeight: lineHeight, limit: 8))
    }

    @Test func nineLinesExceedInlineLimit() {
        let h = OverlayLayout.textHeight(lines(9), width: 600, font: font)
        #expect(OverlayLayout.exceedsLines(textHeight: h, lineHeight: lineHeight, limit: 8))
    }

    // MARK: Preview 50-line cap

    @Test func previewFitsShortText() {
        let h = OverlayLayout.textHeight(lines(10), width: 388, font: font)
        let area = OverlayLayout.previewTextAreaHeight(textHeight: h, lineHeight: lineHeight, maxLines: 50)
        #expect(area == h + OverlayLayout.lineSlack)
    }

    @Test func previewCapsAtMaxLines() {
        let h = OverlayLayout.textHeight(lines(200), width: 388, font: font)
        let area = OverlayLayout.previewTextAreaHeight(textHeight: h, lineHeight: lineHeight, maxLines: 50)
        #expect(area == ceil(lineHeight * 50) + OverlayLayout.lineSlack)
        #expect(area < h)
    }

    @Test func previewHeightIsSameForAnyNoteOverTheCap() {
        let cap = { (n: Int) in
            OverlayLayout.previewTextAreaHeight(
                textHeight: OverlayLayout.textHeight(self.lines(n), width: 388, font: self.font),
                lineHeight: self.lineHeight, maxLines: 50)
        }
        #expect(cap(60) == cap(500))
    }

    // MARK: Preview placement

    let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)

    private func horizontal(parentX: CGFloat) -> (x: CGFloat, width: CGFloat, slideFrom: CGFloat) {
        OverlayLayout.previewHorizontal(
            parent: NSRect(x: parentX, y: 300, width: 640, height: 400),
            visible: screen, preferredWidth: 420, minWidth: 300)
    }

    @Test func previewGoesRightWhenThereIsRoom() {
        let p = horizontal(parentX: 100) // 100+640+10 = 750; 750+420 fits in 1440
        #expect(p.x == 750)
        #expect(p.width == 420)
        #expect(p.slideFrom < 0) // slides in from the parent side
    }

    @Test func previewFlipsLeftNearRightEdge() {
        let p = horizontal(parentX: 780) // right side has no room, left has 762
        #expect(p.x + p.width == CGFloat(780 - 10))
        #expect(p.width == 420)
        #expect(p.slideFrom > 0)
    }

    @Test func previewPicksTheRoomierSideEvenWhenTheRightWouldFit() {
        // 1920-wide screen: the right has 462pt (enough for 420), but the left has
        // 782pt — more room wins, so it goes left.
        let wide = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let p = OverlayLayout.previewHorizontal(
            parent: NSRect(x: 800, y: 300, width: 640, height: 400),
            visible: wide, preferredWidth: 420, minWidth: 300)
        #expect(p.x + p.width == CGFloat(800 - 10))
        #expect(p.width == 420)
        #expect(p.slideFrom > 0)
    }

    @Test func previewNarrowsInsteadOfCoveringCenteredParent() {
        // Centered 640 overlay on a 1440 screen leaves 382pt usable per side: too
        // little for 420, so it narrows to fit rather than overlapping the parent.
        let parent = NSRect(x: 400, y: 300, width: 640, height: 400)
        let p = horizontal(parentX: 400)
        let frame = NSRect(x: p.x, y: 0, width: p.width, height: 10)
        #expect(p.width == 382)
        #expect(frame.maxX <= parent.minX || frame.minX >= parent.maxX)
    }

    @Test func previewNeverNarrowerThanMinimum() {
        let tiny = OverlayLayout.previewHorizontal(
            parent: NSRect(x: 100, y: 0, width: 1240, height: 400),
            visible: screen, preferredWidth: 420, minWidth: 300)
        #expect(tiny.width == 300)
        #expect(screen.contains(NSRect(x: tiny.x, y: 0, width: tiny.width, height: 10)))
    }

    @Test func previewIsTopAlignedWithAnchor() {
        let anchor = NSRect(x: 0, y: 600, width: 600, height: 48)
        #expect(OverlayLayout.previewY(anchor: anchor, height: 300, visible: screen) == CGFloat(648 - 300))
    }

    @Test func previewIsClampedOnScreenVertically() {
        // Anchor near the bottom: a top-aligned preview would fall off-screen.
        let anchor = NSRect(x: 0, y: 20, width: 600, height: 48)
        #expect(OverlayLayout.previewY(anchor: anchor, height: 300, visible: screen) == 8)
    }

    // MARK: Remembered position

    let size = NSSize(width: 640, height: 400)

    @Test func restoresSavedOriginOnScreen() {
        let saved = NSPoint(x: 100, y: 200)
        #expect(OverlayLayout.restoredOrigin(saved, size: size, screens: [screen]) == saved)
    }

    @Test func clampsSavedOriginThatHangsOffScreen() {
        let saved = NSPoint(x: 1200, y: 700) // partly off the right/top edges
        let origin = OverlayLayout.restoredOrigin(saved, size: size, screens: [screen])
        #expect(origin == NSPoint(x: 1440 - 640, y: 900 - 400))
    }

    @Test func ignoresSavedOriginOnMissingDisplay() {
        // Saved on a second display to the right that's no longer connected.
        let saved = NSPoint(x: 2000, y: 200)
        #expect(OverlayLayout.restoredOrigin(saved, size: size, screens: [screen]) == nil)
    }

    @Test func restoresOntoTheDisplayItWasOn() {
        let second = NSRect(x: 1440, y: 0, width: 1920, height: 1080)
        let saved = NSPoint(x: 2000, y: 300)
        #expect(OverlayLayout.restoredOrigin(saved, size: size, screens: [screen, second]) == saved)
    }

    @Test func defaultOriginIsCenteredHorizontally() {
        let origin = OverlayLayout.defaultOrigin(size: size, visible: screen)
        #expect(origin.x == CGFloat(1440 - 640) / 2)
        #expect(origin.y > screen.midY - size.height) // sits a bit above center
        #expect(screen.contains(NSRect(origin: origin, size: size)))
    }
}
