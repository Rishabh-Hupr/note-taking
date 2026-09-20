import AppKit

// PutViewController is the add-note overlay: a Key field and a Value field.
// Enter in Key jumps to Value (if empty) or saves; Enter in Value saves; Esc cancels.
@MainActor
final class PutViewController: NSViewController {
    private let sidecar: SidecarClient
    var onDismiss: (() -> Void)?

    private let keyField = NSTextField()
    private let valueField = NSTextField()
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
        view.frame = NSRect(x: 0, y: 0, width: 640, height: 180)

        configure(keyField, placeholder: "Key", size: 20, weight: .regular)
        configure(valueField, placeholder: "Value", size: 16, weight: .light)
        keyField.nextKeyView = valueField
        valueField.nextKeyView = keyField
        keyField.delegate = self
        valueField.delegate = self

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.stringValue = "⏎ save    ⎋ cancel"
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        [keyField, valueField, statusLabel].forEach { view.addSubview($0) }
        NSLayoutConstraint.activate([
            keyField.topAnchor.constraint(equalTo: view.topAnchor, constant: 22),
            keyField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            keyField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            valueField.topAnchor.constraint(equalTo: keyField.bottomAnchor, constant: 16),
            valueField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            valueField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            statusLabel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -14),
        ])
    }

    private func configure(_ field: NSTextField, placeholder: String, size: CGFloat, weight: NSFont.Weight) {
        field.translatesAutoresizingMaskIntoConstraints = false
        field.placeholderString = placeholder
        field.font = .systemFont(ofSize: size, weight: weight)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
    }

    // Called by AppDelegate each time the put overlay is summoned.
    func prepareForShow() {
        keyField.stringValue = ""
        valueField.stringValue = ""
        statusLabel.stringValue = "⏎ save    ⎋ cancel"
        view.window?.makeFirstResponder(keyField)
    }

    private func save() {
        let key = keyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = valueField.stringValue
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
            if control === keyField, valueField.stringValue.isEmpty {
                view.window?.makeFirstResponder(valueField)
            } else {
                save()
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
