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
        #expect(area == h + 2)
    }

    @Test func previewCapsAtMaxLines() {
        let h = OverlayLayout.textHeight(lines(200), width: 388, font: font)
        let area = OverlayLayout.previewTextAreaHeight(textHeight: h, lineHeight: lineHeight, maxLines: 50)
        #expect(area == ceil(lineHeight * 50))
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
