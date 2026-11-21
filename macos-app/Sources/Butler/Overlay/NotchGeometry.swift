import AppKit

// Where the search window grows from: the MacBook's notch, or a pretend one at
// the top centre of a screen without a notch. Pure geometry (screen numbers in,
// rects out) so it's unit-tested without a real display.
enum NotchGeometry {
    /// Width of the pretend notch on screens without one (about a real notch's).
    static let fakeNotchWidth: CGFloat = 200
    /// Its height when the menu bar is hidden (no strip to measure).
    static let fallbackMenuBarHeight: CGFloat = 24

    /// What we need to know about a screen, read from NSScreen.
    struct Screen {
        var frame: NSRect
        var visibleFrame: NSRect
        /// The notch's height (NSScreen.safeAreaInsets.top), 0 without a notch.
        var safeAreaTop: CGFloat
        /// The menu-bar strips left and right of the notch, nil without a notch.
        var leftOfNotch: NSRect?
        var rightOfNotch: NSRect?

        init(frame: NSRect, visibleFrame: NSRect, safeAreaTop: CGFloat = 0,
             leftOfNotch: NSRect? = nil, rightOfNotch: NSRect? = nil) {
            self.frame = frame
            self.visibleFrame = visibleFrame
            self.safeAreaTop = safeAreaTop
            self.leftOfNotch = leftOfNotch
            self.rightOfNotch = rightOfNotch
        }

        @MainActor init(_ screen: NSScreen) {
            self.init(frame: screen.frame, visibleFrame: screen.visibleFrame,
                      safeAreaTop: screen.safeAreaInsets.top,
                      leftOfNotch: screen.auxiliaryTopLeftArea, rightOfNotch: screen.auxiliaryTopRightArea)
        }
    }

    /// The notch in screen coordinates: the gap between the two menu-bar strips
    /// on a notched screen, else a pretend notch the menu bar's height, centred.
    static func notch(on screen: Screen) -> NSRect {
        let top = screen.frame.maxY
        if screen.safeAreaTop > 0, let left = screen.leftOfNotch, let right = screen.rightOfNotch,
           right.minX > left.maxX {
            return NSRect(x: left.maxX, y: top - screen.safeAreaTop,
                          width: right.minX - left.maxX, height: screen.safeAreaTop)
        }
        let menuBar = top - screen.visibleFrame.maxY
        let height = menuBar > 0 ? menuBar : fallbackMenuBarHeight
        return NSRect(x: screen.frame.midX - fakeNotchWidth / 2, y: top - height,
                      width: fakeNotchWidth, height: height)
    }

    /// The black panel's rect: `bodySize` wide and tall, its top edge on the
    /// screen's top edge (so it merges with the notch), centred on the notch and
    /// kept on screen.
    static func bodyFrame(notch: NSRect, screen: Screen, bodySize: NSSize) -> NSRect {
        var x = notch.midX - bodySize.width / 2
        // Keep it on screen; if it's wider than the screen, pin it to the left edge.
        x = max(min(x, screen.frame.maxX - bodySize.width), screen.frame.minX)
        return NSRect(x: x, y: screen.frame.maxY - bodySize.height, width: bodySize.width, height: bodySize.height)
    }

    /// The window's frame: the body plus a transparent margin left, right and
    /// below, so the spring's overshoot isn't cut off. The top stays on the body.
    static func windowFrame(body: NSRect, margin: CGFloat) -> NSRect {
        NSRect(x: body.minX - margin, y: body.minY - margin,
               width: body.width + margin * 2, height: body.height + margin)
    }
}
