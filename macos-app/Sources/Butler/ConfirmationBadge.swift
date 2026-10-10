import AppKit

// A big centered "✓ Saved" badge that pops in over a dialog — readable at a
// glance, so the dialog can close sooner than a small footer message allows.
@MainActor
final class ConfirmationBadge: NSVisualEffectView {
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")

    init(symbol: String = "checkmark.circle.fill", text: String = "Saved", tint: NSColor = .systemGreen) {
        super.init(frame: .zero)
        material = .popover
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 16
        layer?.masksToBounds = true
        translatesAutoresizingMaskIntoConstraints = false
        isHidden = true

        let config = NSImage.SymbolConfiguration(pointSize: 40, weight: .semibold)
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: text)?
            .withSymbolConfiguration(config)
        icon.contentTintColor = tint
        icon.translatesAutoresizingMaskIntoConstraints = false

        label.stringValue = text
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.textColor = tint
        label.translatesAutoresizingMaskIntoConstraints = false

        addSubview(icon)
        addSubview(label)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 120),
            heightAnchor.constraint(equalToConstant: 100),
            icon.centerXAnchor.constraint(equalTo: centerXAnchor),
            icon.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 6),
        ])
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    /// Fade in and give the tick a bounce.
    func pop() {
        isHidden = false
        alphaValue = 0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            animator().alphaValue = 1
        }
        if #available(macOS 14.0, *) {
            icon.addSymbolEffect(.bounce)
        }
    }

    func hide() {
        isHidden = true
        alphaValue = 0
    }
}
