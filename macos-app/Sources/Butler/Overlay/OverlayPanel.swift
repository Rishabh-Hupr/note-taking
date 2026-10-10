import AppKit

// OverlayPanel is the Spotlight-style floating window: borderless-looking,
// non-activating (so summoning it doesn't steal the active app), on all Spaces.
final class OverlayPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            // .titled + transparent titlebar (instead of fully .borderless) keeps
            // key-window/focus behavior reliable while still looking chromeless.
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true

        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        hidesOnDeactivate = false
        isReleasedWhenClosed = false // reused across summons — never deallocate
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true

        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
    }

    // Borderless/non-activating panels refuse key status by default, which would
    // block typing in the search field. Force it on.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
