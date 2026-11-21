import AppKit
import QuartzCore

// The notch-shaped background of the search window, and its Dynamic Island-
// style spring: it grows out of the notch on open and shrinks back into it on
// close. Solid black in the notch strip at the top (so it merges with the
// hardware notch), fading to a translucent dark blur below.
//
// The window stays full size the whole time; only this view's mask animates.
// Resizing the window every frame would re-lay out the list and stutter. The
// window also has a transparent margin (`overshootMargin`) left, right and
// below, so the spring can overshoot a little without being cut off.
final class NotchContainerView: NSVisualEffectView {
    static let overshootMargin: CGFloat = 16
    /// How opaque the black is below the notch strip (1 = solid). The top strip
    /// is always solid; it fades to this over `fadeLength`.
    static let bodyOpacity: CGFloat = 0.6
    static let fadeLength: CGFloat = 40
    static let bottomRadius: CGFloat = 22
    /// The outward curve where the panel's sides meet the top of the screen,
    /// so it reads as the notch flowing down rather than a box under it.
    static let topFlare: CGFloat = 10

    /// The content area (the black shape at full size). Lay subviews out in here.
    let body = NSView()
    private let shape = CAShapeLayer()
    private let tint = GradientView()
    private var animating = false

    /// Height of the notch strip at the top, kept solid black.
    var notchHeight: CGFloat = 32 { didSet { needsLayout = true } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        material = .hudWindow
        blendingMode = .behindWindow
        state = .active
        appearance = NSAppearance(named: .darkAqua)
        wantsLayer = true
        layer?.mask = shape // on the blur view's own layer, so the blur follows the shape
        tint.frame = bounds
        tint.autoresizingMask = [.width, .height]
        addSubview(tint)
        body.translatesAutoresizingMaskIntoConstraints = false
        addSubview(body)
        let m = Self.overshootMargin
        NSLayoutConstraint.activate([
            body.topAnchor.constraint(equalTo: topAnchor),
            body.leadingAnchor.constraint(equalTo: leadingAnchor, constant: m),
            body.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -m),
            body.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -m),
        ])
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    /// The full shape's rect in this view: everything but the margin.
    private var bodyRect: NSRect {
        let m = Self.overshootMargin
        return NSRect(x: m, y: m, width: bounds.width - m * 2, height: bounds.height - m)
    }

    private var fullPath: CGPath {
        Self.path(for: bodyRect, flare: Self.topFlare, bottomRadius: Self.bottomRadius)
    }

    private func notchPath(_ notch: NSRect) -> CGPath {
        Self.path(for: notch, flare: 3, bottomRadius: min(notch.height / 2, 10))
    }

    override func layout() {
        super.layout()
        if !animating { shape.path = fullPath }
        // Black over the blur: solid down through the notch strip, then fading
        // to bodyOpacity. Gradient points run bottom (0) to top (1).
        let height = max(bounds.height, 1)
        let solidUntil = min(1, notchHeight / height)
        let fadedBy = min(1, (notchHeight + Self.fadeLength) / height)
        let solid = NSColor.black.cgColor
        let faded = NSColor.black.withAlphaComponent(Self.bodyOpacity).cgColor
        tint.gradient.colors = [faded, faded, solid, solid]
        tint.gradient.locations = [0, NSNumber(value: Double(1 - fadedBy)), NSNumber(value: Double(1 - solidUntil)), 1]
    }

    /// Grow from `notch` (in this view's coordinates) to full size with a quick
    /// spring; the content fades in as it opens. Typing works throughout.
    func animateOpen(fromNotch notch: NSRect) {
        animating = true
        shape.removeAllAnimations()
        body.layer?.removeAllAnimations()
        let spring = CASpringAnimation(keyPath: "path")
        spring.fromValue = notchPath(notch)
        spring.toValue = fullPath
        spring.mass = 1
        spring.stiffness = 320
        spring.damping = 24 // a little bounce, like the Dynamic Island
        spring.duration = spring.settlingDuration
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in self?.animating = false }
        shape.path = fullPath
        shape.add(spring, forKey: "open")
        CATransaction.commit()

        body.alphaValue = 0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            body.animator().alphaValue = 1
        }
    }

    /// Shrink back into `notch`, then call `completion`.
    func animateClose(toNotch notch: NSRect, completion: @escaping () -> Void) {
        animating = true
        let shrink = CABasicAnimation(keyPath: "path")
        shrink.fromValue = shape.presentation()?.path ?? fullPath
        shrink.toValue = notchPath(notch)
        shrink.duration = 0.2
        shrink.timingFunction = CAMediaTimingFunction(name: .easeIn)
        shrink.fillMode = .forwards
        shrink.isRemovedOnCompletion = false
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            self?.shape.removeAllAnimations()
            self?.shape.path = self?.fullPath
            self?.animating = false
            completion()
        }
        shape.add(shrink, forKey: "close")
        CATransaction.commit()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            body.animator().alphaValue = 0
        }
    }

    /// The notch shape for `rect`: a flat top on the screen edge that curves
    /// outward by `flare` at both ends, straight sides, rounded bottom corners.
    /// Always the same elements in the same order, so two of these (notch-sized
    /// and full-sized) animate smoothly into each other.
    static func path(for rect: NSRect, flare: CGFloat, bottomRadius r: CGFloat) -> CGPath {
        let p = CGMutablePath()
        let top = rect.maxY
        p.move(to: CGPoint(x: rect.minX - flare, y: top))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: top - flare), control: CGPoint(x: rect.minX, y: top))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        p.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + r), control: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: top - flare))
        p.addQuadCurve(to: CGPoint(x: rect.maxX + flare, y: top), control: CGPoint(x: rect.maxX, y: top))
        p.closeSubpath()
        return p
    }
}

/// A view drawn by a vertical CAGradientLayer (bottom to top).
final class GradientView: NSView {
    let gradient = CAGradientLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        gradient.startPoint = CGPoint(x: 0.5, y: 0)
        gradient.endPoint = CGPoint(x: 0.5, y: 1)
        layer = gradient
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError("not used") }
}
