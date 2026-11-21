import AppKit

// OverlayPanel is the floating overlay window (search, add note): borderless-
// looking, non-activating (so summoning it doesn't steal the active app), on all
// Spaces, always dark, hanging from the notch over the menu bar (NotchPresenter
// places it), so it isn't draggable.
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
        isMovableByWindowBackground = false
        appearance = NSAppearance(named: .darkAqua)

        isFloatingPanel = true
        level = .statusBar // above the menu bar, which the notch strip covers
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

    // The panel's top is the screen's top edge (over the menu bar); AppKit
    // would otherwise push a titled window down below the menu bar.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    // Borderless/non-activating panels refuse key status by default, which would
    // block typing in the search field. Force it on.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    // Standard editing shortcuts (⌘C/⌘V/⌘Z…), dispatched here because the menu's
    // key equivalents never fire for a non-activating panel. The shortcut list lives
    // in EditingShortcuts, shared with the Edit menu.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if let action = EditingShortcuts.action(for: event),
           NSApp.sendAction(action, to: nil, from: self) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
