import AppKit

// A small "•  ••  •••" cycling indicator that says "search in progress" while the
// typing debounce waits and the backend replies. Invisible when stopped.
@MainActor
final class LoadingDots: NSTextField {
    private var animation: Task<Void, Never>?
    private static let frames = ["•", "••", "•••"]

    init() {
        super.init(frame: .zero)
        isEditable = false
        isSelectable = false
        isBordered = false
        drawsBackground = false
        font = .systemFont(ofSize: 18, weight: .semibold)
        textColor = .tertiaryLabelColor
        alignment = .right
        stringValue = ""
        translatesAutoresizingMaskIntoConstraints = false
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    func start() {
        guard animation == nil else { return } // keep the cycle smooth across keystrokes
        animation = Task { [weak self] in
            var i = 0
            while !Task.isCancelled {
                self?.stringValue = Self.frames[i % Self.frames.count]
                i += 1
                try? await Task.sleep(nanoseconds: 180_000_000)
            }
        }
    }

    func stop() {
        animation?.cancel()
        animation = nil
        stringValue = ""
    }
}
