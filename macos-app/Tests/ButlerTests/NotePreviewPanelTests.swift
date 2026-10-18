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
}
