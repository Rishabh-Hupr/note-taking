import AppKit

/// A view controller whose window grows out of the notch: its view is a
/// NotchContainerView, and it keeps its content clear of the notch strip.
@MainActor
protocol NotchHosting: NSViewController {
    var notchView: NotchContainerView { get }
    /// Called before each open with the notch strip's height on that screen.
    func setNotchHeight(_ height: CGFloat)
}

/// Opens and closes one overlay window from the notch: places it on the mouse's
/// screen, springs it open, shrinks it back on close. Shared by search and
/// add-note so both behave exactly alike.
@MainActor
final class NotchPresenter {
    let panel: OverlayPanel
    private let host: NotchHosting
    /// The content's size below the notch strip.
    private let contentSize: NSSize
    // Where the notch was on the last open, in the window's coordinates: the
    // close animation shrinks back into it.
    private var notchInWindow = NSRect.zero
    // Bumped per open/close, so a close finishing after a re-open can't hide it.
    private var generation = 0
    private var closing = false

    init(host: NotchHosting, contentSize: NSSize) {
        self.host = host
        self.contentSize = contentSize
        panel = OverlayPanel(contentRect: NSRect(origin: .zero, size: contentSize))
        panel.contentViewController = host
    }

    /// Open, and fully visible (not on its way out).
    var isOpen: Bool { panel.isVisible && !closing }

    /// Grow out of the notch of the screen the mouse is on (or a pretend one) and
    /// take keyboard focus. Already open: just keeps focus, no replayed animation.
    func open() {
        let alreadyOpen = isOpen
        generation += 1
        closing = false
        let mouse = NSEvent.mouseLocation
        if !alreadyOpen, let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main {
            let geometry = NotchGeometry.Screen(screen)
            let notch = NotchGeometry.notch(on: geometry)
            let body = NotchGeometry.bodyFrame(
                notch: notch, screen: geometry,
                bodySize: NSSize(width: contentSize.width, height: contentSize.height + notch.height))
            let frame = NotchGeometry.windowFrame(body: body, margin: NotchContainerView.overshootMargin)
            panel.setFrame(frame, display: false)
            host.setNotchHeight(notch.height)
            notchInWindow = notch.offsetBy(dx: -frame.minX, dy: -frame.minY)
        }
        panel.makeKeyAndOrderFront(nil)
        if !alreadyOpen { host.notchView.animateOpen(fromNotch: notchInWindow) }
    }

    /// Shrink back into the notch, then hide.
    func close() {
        guard isOpen else { return }
        generation += 1
        closing = true
        let current = generation
        host.notchView.animateClose(toNotch: notchInWindow) { [weak self] in
            guard let self, current == self.generation else { return } // re-opened meanwhile
            closing = false
            panel.orderOut(nil)
        }
    }

    /// Hide at once, no animation (when the other overlay takes the notch).
    func hideNow() {
        generation += 1
        closing = false
        panel.orderOut(nil)
    }
}
