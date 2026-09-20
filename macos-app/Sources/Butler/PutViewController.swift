import AppKit

// A multi-line text view for the value that intercepts ⌘Return (save) and Esc
// (cancel); plain Return inserts a newline as usual.
final class ValueTextView: NSTextView {
    var onSave: (() -> Void)?
    var onCancel: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 { // Return
            if event.modifierFlags.contains(.command) {
                insertNewline(nil) // ⌘Return → newline
            } else {
                onSave?() // Return → save
            }
            return
        }
        if event.keyCode == 53 { // Esc
            onCancel?()
            return
        }
        super.keyDown(with: event)
    }
}

// PutViewController is the add-note overlay: a single-line Key field and a
// multi-line Value view. Enter in Key advances to Value; in Value it inserts a
// newline. ⌘Return saves from either; Esc cancels.
@MainActor
final class PutViewController: NSViewController {
    private let sidecar: SidecarClient
    var onDismiss: (() -> Void)?

    private let keyField = NSTextField()
    private let valueView = ValueTextView()
    private let statusLabel = NSTextField(labelWithString: "")

    init(sidecar: SidecarClient) {
        self.sidecar = sidecar
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    override func loadView() {
        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.layer?.masksToBounds = true
        self.view = effect
        view.frame = NSRect(x: 0, y: 0, width: 640, height: 178)

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
        valueView.font = .systemFont(ofSize: 16, weight: .light)
        valueView.drawsBackground = false
        valueView.textContainerInset = NSSize(width: 0, height: 4)
        valueView.isVerticallyResizable = true
        valueView.isHorizontallyResizable = false
        valueView.textContainer?.widthTracksTextView = true
        valueView.autoresizingMask = [.width]
        valueView.onSave = { [weak self] in self?.save() }
        valueView.onCancel = { [weak self] in self?.onDismiss?() }
        scroll.documentView = valueView

        keyField.nextKeyView = valueView
        valueView.nextKeyView = keyField

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.stringValue = "⏎ save    ⌘⏎ newline    ⎋ cancel"
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        [keyField, scroll, statusLabel].forEach { view.addSubview($0) }
        NSLayoutConstraint.activate([
            keyField.topAnchor.constraint(equalTo: view.topAnchor, constant: 22),
            keyField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            keyField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            scroll.topAnchor.constraint(equalTo: keyField.bottomAnchor, constant: 14),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            scroll.heightAnchor.constraint(equalToConstant: 78), // ~3 lines, then scrolls

            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            statusLabel.topAnchor.constraint(greaterThanOrEqualTo: scroll.bottomAnchor, constant: 10),
            statusLabel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -14),
        ])
    }

    // Called by AppDelegate each time the put overlay is summoned.
    func prepareForShow() {
        keyField.stringValue = ""
        valueView.string = ""
        statusLabel.stringValue = "⏎ save    ⌘⏎ newline    ⎋ cancel"
        view.window?.makeFirstResponder(keyField)
    }

    private func save() {
        let key = keyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = valueView.string
        guard !key.isEmpty, !value.isEmpty else {
            statusLabel.stringValue = "Both key and value are required"
            return
        }
        Task { [weak self] in
            guard let self else { return }
            do {
                try await sidecar.put(key: key, value: value)
                onDismiss?()
            } catch {
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
