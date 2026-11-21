import AppKit

// A multi-line text view for the value: Return inserts a newline, ⌘Return saves,
// Esc cancels.
final class ValueTextView: NSTextView {
    var onSave: (() -> Void)?
    var onCancel: (() -> Void)?
    var onShiftTab: (() -> Void)?
    var placeholder: String = ""

    // NSTextView has no placeholder, so draw one while empty.
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholder.isEmpty else { return }
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.placeholderTextColor,
            .font: font ?? NSFont.systemFont(ofSize: 16),
        ]
        let origin = NSPoint(
            x: textContainerInset.width + (textContainer?.lineFragmentPadding ?? 5),
            y: textContainerInset.height
        )
        placeholder.draw(at: origin, withAttributes: attrs)
    }

    override func didChangeText() {
        super.didChangeText()
        needsDisplay = true // keep the placeholder in sync as text appears/clears
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 { // Return
            if event.modifierFlags.contains(.command) {
                onSave?() // ⌘Return → save
            } else {
                insertNewline(nil) // Return → newline
            }
            return
        }
        if event.keyCode == 53 { // Esc
            onCancel?()
            return
        }
        if event.keyCode == 48, event.modifierFlags.contains(.shift) { // Shift+Tab
            onShiftTab?() // back to the Key field
            return
        }
        super.keyDown(with: event)
    }
}

// PutViewController is the add-note overlay: a single-line Key field and a
// multi-line Value view. Return in Key advances to Value; Return in Value saves
// (⌘Return inserts a newline); Esc cancels. Drafts persist across dismissals and
// are cleared only after a successful save.
@MainActor
final class PutViewController: NSViewController, NotchHosting {
    private let sidecar: SidecarClient
    var onDismiss: (() -> Void)?
    var onSaved: (() -> Void)? // e.g. refresh search's cached recent notes

    private let keyField = NSTextField()
    private let valueView = ValueTextView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let savedBadge = ConfirmationBadge()
    // How long the "Saved" badge shows before the dialog closes.
    private let savedConfirmationDuration: UInt64 = 400_000_000
    // Bumped each time the dialog is shown, so a pending post-save dismiss from an
    // earlier save can't close a dialog the user has since reopened.
    private var showGeneration = 0

    init(sidecar: SidecarClient) {
        self.sidecar = sidecar
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    /// Size of the panel's content below the notch strip.
    static let contentSize = NSSize(width: 640, height: 178)

    /// The notch-shaped dark background; NotchPresenter runs its open/close spring.
    private(set) lazy var notchView = NotchContainerView(frame: NSRect(origin: .zero, size: Self.contentSize))
    private var keyTopConstraint: NSLayoutConstraint?

    /// Keep the key field clear of the notch strip at the top.
    func setNotchHeight(_ height: CGFloat) {
        keyTopConstraint?.constant = height + 14
        notchView.notchHeight = height
    }

    override func loadView() {
        // Always dark: black at the notch, a translucent dark blur below.
        self.view = notchView
        let body = notchView.body

        // Key (single line)
        keyField.translatesAutoresizingMaskIntoConstraints = false
        keyField.placeholderString = "Key"
        keyField.font = .systemFont(ofSize: 20)
        keyField.isBordered = false
        keyField.drawsBackground = false
        keyField.focusRingType = .none
        keyField.delegate = self

        // Value (multi-line, ~3 lines then scrolls)
        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true

        valueView.isRichText = false
        valueView.allowsUndo = true // ⌘Z / ⇧⌘Z (dispatched by OverlayPanel)
        valueView.font = .systemFont(ofSize: 16, weight: .light)
        valueView.drawsBackground = false
        valueView.textContainerInset = NSSize(width: 0, height: 4)
        valueView.isVerticallyResizable = true
        valueView.isHorizontallyResizable = false
        valueView.textContainer?.widthTracksTextView = true
        valueView.autoresizingMask = [.width]
        valueView.placeholder = "Value"
        valueView.onSave = { [weak self] in self?.save() }
        valueView.onCancel = { [weak self] in self?.onDismiss?() }
        valueView.onShiftTab = { [weak self] in
            guard let self else { return }
            self.view.window?.makeFirstResponder(self.keyField)
        }
        scroll.documentView = valueView

        keyField.nextKeyView = valueView
        valueView.nextKeyView = keyField

        statusLabel.font = .systemFont(ofSize: 11)
        showShortcuts()
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        [keyField, scroll, statusLabel].forEach { body.addSubview($0) }
        body.addSubview(savedBadge) // last, so it sits on top of the fields
        let keyTop = keyField.topAnchor.constraint(equalTo: body.topAnchor, constant: 22)
        keyTopConstraint = keyTop
        NSLayoutConstraint.activate([
            keyTop,
            keyField.leadingAnchor.constraint(equalTo: body.leadingAnchor, constant: 20),
            keyField.trailingAnchor.constraint(equalTo: body.trailingAnchor, constant: -20),

            scroll.topAnchor.constraint(equalTo: keyField.bottomAnchor, constant: 14),
            scroll.leadingAnchor.constraint(equalTo: body.leadingAnchor, constant: 20),
            scroll.trailingAnchor.constraint(equalTo: body.trailingAnchor, constant: -20),
            scroll.heightAnchor.constraint(equalToConstant: 78), // ~3 lines, then scrolls

            statusLabel.leadingAnchor.constraint(equalTo: body.leadingAnchor, constant: 20),
            statusLabel.topAnchor.constraint(greaterThanOrEqualTo: scroll.bottomAnchor, constant: 10),
            statusLabel.bottomAnchor.constraint(equalTo: body.bottomAnchor, constant: -14),

            savedBadge.centerXAnchor.constraint(equalTo: body.centerXAnchor),
            savedBadge.centerYAnchor.constraint(equalTo: body.centerYAnchor),
        ])
    }

    // Called by AppDelegate each time the put overlay is summoned. The draft is
    // intentionally NOT cleared here — an accidental dismiss keeps your text so
    // re-summoning restores it. Fields are cleared only after a successful save.
    func prepareForShow() {
        showGeneration += 1
        savedBadge.hide()
        showShortcuts()
        valueView.needsDisplay = true
        // Resume where you left off: value if the key is already filled, else key.
        view.window?.makeFirstResponder(keyField.stringValue.isEmpty ? keyField : valueView)
    }

    // The shortcut hints in the status line (replaced by errors until the next show).
    private func showShortcuts() {
        statusLabel.attributedStringValue = ShortcutHints.text(ShortcutHints.put)
    }

    private func save() {
        let key = keyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = valueView.string
        // Blank lines alone don't count as a value (the backend also trims
        // leading/trailing whitespace off whatever is saved).
        guard !key.isEmpty, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            statusLabel.textColor = .secondaryLabelColor
            statusLabel.stringValue = "Both key and value are required"
            return
        }
        Task { [weak self] in
            guard let self else { return }
            do {
                try await sidecar.put(key: key, value: value)
                onSaved?()
                // Success: clear the draft and pop a big "Saved" tick, then close.
                let generation = showGeneration
                keyField.stringValue = ""
                valueView.string = ""
                valueView.needsDisplay = true
                savedBadge.pop()
                try? await Task.sleep(nanoseconds: savedConfirmationDuration)
                // Reopened meanwhile? Then that's a fresh dialog — leave it open.
                guard generation == showGeneration else { return }
                savedBadge.hide()
                onDismiss?()
            } catch {
                statusLabel.textColor = .systemRed
                statusLabel.stringValue = "Save failed — try again"
            }
        }
    }
}

extension PutViewController: NSTextFieldDelegate {
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            // ⌘Return from the key field saves; plain Return advances to value.
            if NSApp.currentEvent?.modifierFlags.contains(.command) == true {
                save()
            } else {
                view.window?.makeFirstResponder(valueView)
            }
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            onDismiss?()
            return true
        default:
            return false
        }
    }
}
