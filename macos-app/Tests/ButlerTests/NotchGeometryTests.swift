import AppKit
import Testing
@testable import Butler

@Suite struct NotchGeometryTests {
    // A 14" MacBook Pro at its default scaling, as macOS reports it (read from
    // a real one): 1512×982pt, the notch 185pt wide and 32pt tall between the
    // two menu-bar strips.
    private let macBook14 = NotchGeometry.Screen(
        frame: NSRect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: NSRect(x: 0, y: 0, width: 1512, height: 949),
        safeAreaTop: 32,
        leftOfNotch: NSRect(x: 0, y: 950, width: 663, height: 32),
        rightOfNotch: NSRect(x: 848, y: 950, width: 664, height: 32))
    // A 16" MacBook Pro at its default scaling: a wider screen (1728×1117pt) with
    // the same physical notch, so about the same size in points, centred.
    // Representative values; the code only reads whatever the screen reports.
    private let macBook16 = NotchGeometry.Screen(
        frame: NSRect(x: 0, y: 0, width: 1728, height: 1117),
        visibleFrame: NSRect(x: 0, y: 0, width: 1728, height: 1084),
        safeAreaTop: 32,
        leftOfNotch: NSRect(x: 0, y: 1085, width: 771, height: 32),
        rightOfNotch: NSRect(x: 957, y: 1085, width: 771, height: 32))
    // An external 1920×1080 monitor to the right, 25pt menu bar, no notch.
    private let external = NotchGeometry.Screen(
        frame: NSRect(x: 1512, y: 0, width: 1920, height: 1080),
        visibleFrame: NSRect(x: 1512, y: 0, width: 1920, height: 1055))

    @Test func findsTheRealNotchBetweenTheMenuBarStrips() {
        #expect(NotchGeometry.notch(on: macBook14) == NSRect(x: 663, y: 950, width: 185, height: 32))
    }

    // A 16" (wider, taller screen): the notch comes from its own menu-bar
    // strips, and the panel still hangs from the top, centred on it.
    @Test func sixteenInchMacBookUsesItsOwnNotch() {
        let notch = NotchGeometry.notch(on: macBook16)
        #expect(notch == NSRect(x: 771, y: 1085, width: 186, height: 32))
        #expect(notch.midX == macBook16.frame.midX)
        let body = NotchGeometry.bodyFrame(notch: notch, screen: macBook16, bodySize: NSSize(width: 640, height: 624))
        #expect(body.maxY == macBook16.frame.maxY)
        #expect(body.midX == notch.midX)
        #expect(macBook16.frame.contains(body))
    }

    // The same 16" as a second screen, to the right of the 14": coordinates are
    // relative to the whole desktop, and the notch is still found on it.
    @Test func notchOnASecondScreenUsesThatScreensCoordinates() {
        var right = macBook16
        right.frame.origin.x = 1512
        right.visibleFrame.origin.x = 1512
        right.leftOfNotch?.origin.x = 1512
        right.rightOfNotch?.origin.x = 1512 + 957
        #expect(NotchGeometry.notch(on: right) == NSRect(x: 1512 + 771, y: 1085, width: 186, height: 32))
    }

    @Test func pretendsANotchOnScreensWithoutOne() {
        let notch = NotchGeometry.notch(on: external)
        #expect(notch.width == NotchGeometry.fakeNotchWidth)
        #expect(notch.midX == external.frame.midX)
        #expect(notch.maxY == external.frame.maxY && notch.height == 25) // the menu bar's height
    }

    @Test func hiddenMenuBarStillGetsAPretendNotch() {
        var screen = external
        screen.visibleFrame = screen.frame // auto-hidden menu bar
        #expect(NotchGeometry.notch(on: screen).height == NotchGeometry.fallbackMenuBarHeight)
    }

    @Test func panelHangsFromTheTopCentredOnTheNotch() {
        let notch = NotchGeometry.notch(on: macBook14)
        let body = NotchGeometry.bodyFrame(notch: notch, screen: macBook14, bodySize: NSSize(width: 640, height: 624))
        #expect(body.maxY == macBook14.frame.maxY)
        #expect(body.midX == notch.midX)
        #expect(body.width == 640 && body.height == 624)
    }

    @Test func panelStaysOnScreenWhenTheNotchIsNearAnEdge() {
        var screen = external
        screen.frame.size.width = 700
        screen.visibleFrame.size.width = 700
        let body = NotchGeometry.bodyFrame(notch: NotchGeometry.notch(on: screen), screen: screen,
                                           bodySize: NSSize(width: 900, height: 600))
        #expect(body.minX == screen.frame.minX) // wider than the screen: pinned to its left edge
    }

    @Test func windowAddsTheOvershootMarginExceptAtTheTop() {
        let body = NSRect(x: 100, y: 300, width: 640, height: 600)
        let window = NotchGeometry.windowFrame(body: body, margin: 16)
        #expect(window == NSRect(x: 84, y: 284, width: 672, height: 616))
        #expect(window.maxY == body.maxY)
    }

    // Open/close interpolate between a notch-sized and a full-sized shape; that
    // only animates smoothly if both paths have the same elements in order.
    @Test func notchAndFullShapesHaveTheSameStructure() {
        func elements(_ path: CGPath) -> [CGPathElementType] {
            var types: [CGPathElementType] = []
            path.applyWithBlock { types.append($0.pointee.type) }
            return types
        }
        let small = NotchContainerView.path(for: NSRect(x: 240, y: 600, width: 190, height: 32), flare: 3, bottomRadius: 10)
        let full = NotchContainerView.path(for: NSRect(x: 16, y: 16, width: 640, height: 624), flare: 10, bottomRadius: 22)
        #expect(elements(small) == elements(full))
        #expect(full.boundingBox.maxY == 640) // flat top on the screen's edge
    }
}
