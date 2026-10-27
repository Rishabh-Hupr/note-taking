import AppKit
import Testing
@testable import Butler

// Regression: a very wide key used to push the preview past its planned width
// (1193pt instead of 420) — over the search window when placed left, off-screen
// when placed right. The key now wraps and can't widen the panel.
@MainActor @Suite struct NotePreviewPanelTests {
    private let wideKey = String(repeating: "ELMO UI auth (ALB + alb lambda targets for 443 listener) ", count: 3)

    private func present(parentX: CGFloat) -> (panel: NSWindow, parent: NSWindow, screen: NSRect) {
        _ = NSApplication.shared
        let parent = NSWindow(contentRect: NSRect(x: parentX, y: 250, width: 640, height: 592),
                              styleMask: [.titled], backing: .buffered, defer: false)
        parent.orderFrontRegardless()
        let note = Note(id: 1, key: wideKey, value: String(repeating: "body text ", count: 300),
                        createdAt: "", updatedAt: "", rank: 0)
        let panel = NotePreviewPanel()
        panel.present(note, anchor: NSRect(x: parentX + 12, y: 700, width: 600, height: 48), in: parent)
        panel.contentView?.layoutSubtreeIfNeeded()
        let screen = (parent.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        return (panel, parent, screen)
    }

    @Test(arguments: [
        "left",   // search window near the right edge → preview goes left
        "right",  // search window near the left edge → preview goes right
    ])
    func wideKeyStaysInBoundsAndOffTheSearchWindow(side: String) throws {
        let screenWidth = (NSScreen.main?.visibleFrame.width ?? 1440)
        let parentX = side == "left" ? screenWidth - 640 - 40 : 40
        let (panel, parent, screen) = present(parentX: parentX)
        #expect(panel.frame.width <= NotePreviewPanel.preferredWidth)
        #expect(!panel.frame.intersects(parent.frame), "preview \(panel.frame) overlaps search \(parent.frame)")
        #expect(screen.contains(panel.frame), "preview \(panel.frame) leaves the screen \(screen)")
    }
    // Opening the preview costs the same for a 1.5MB note as for a 6KB one: it
    // sizes itself from the note's start and draws only what's visible. Timed
    // alternately, best of 5 each, so parallel tests load both alike.
    @Test func presentingAHugeNoteCostsWhatASmallOneDoes() {
        _ = NSApplication.shared
        let parent = NSWindow(contentRect: NSRect(x: 40, y: 250, width: 640, height: 592),
                              styleMask: [.titled], backing: .buffered, defer: false)
        parent.orderFrontRegardless()
        let line = "  step: ALB authenticate-oidc → lambda (regional_stack.ts), cookie=AWSELB"
        let small = String(repeating: line + "\n", count: 80)
        let huge = String(repeating: small, count: 250)
        let panel = NotePreviewPanel()
        var id = 0
        func ms(_ value: String) -> Double {
            id += 1 // a new note each time, so the text is really replaced
            let note = Note(id: id, key: "k", value: value, createdAt: "", updatedAt: "", rank: 0)
            let start = DispatchTime.now().uptimeNanoseconds
            panel.present(note, anchor: NSRect(x: 52, y: 700, width: 600, height: 48), in: parent)
            panel.displayIfNeeded()
            return Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6
        }
        _ = ms(small) // first show sets up fonts and the window
        var smallMs = Double.infinity, hugeMs = Double.infinity
        for _ in 0..<5 {
            smallMs = min(smallMs, ms(small))
            hugeMs = min(hugeMs, ms(huge))
        }
        #expect(hugeMs < smallMs * 3 + 2, "1.5MB note \(hugeMs)ms vs 6KB \(smallMs)ms")
    }

    // The preview holds the whole note and relies on TextKit 2 laying out only
    // what's on screen. Touching the text view's `layoutManager` silently
    // switches it to TextKit 1, which lays out the whole note up front.
    @Test func previewTextViewLaysOutOnlyWhatsVisible() {
        let (panel, _, _) = present(parentX: 40)
        #expect((panel as? NotePreviewPanel)?.usesViewportLayout == true)
    }
}
