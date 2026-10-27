import AppKit

// The shortcut hints along the bottom of the search and add-note windows,
// defined once: each hint is drawn in its own colour.
enum ShortcutHints {
    struct Hint {
        let keys: String
        let action: String
        let color: NSColor
    }

    static let search: [Hint] = [
        Hint(keys: "↑↓", action: "navigate", color: .systemBlue),
        Hint(keys: "⏎", action: "copy", color: .systemGreen),
        Hint(keys: "⌘D", action: "delete", color: .systemRed),
        Hint(keys: "⎋", action: "close", color: .secondaryLabelColor),
    ]
    static let put: [Hint] = [
        Hint(keys: "⌘⏎", action: "save", color: .systemGreen),
        Hint(keys: "⏎", action: "newline", color: .systemBlue),
        Hint(keys: "⎋", action: "cancel", color: .secondaryLabelColor),
    ]

    static let font = NSFont.systemFont(ofSize: 11)
    private static let gap = "    "

    /// The hints as one line of text, each hint (keys and word) in its colour.
    static func text(_ hints: [Hint]) -> NSAttributedString {
        let line = NSMutableAttributedString()
        for (index, hint) in hints.enumerated() {
            if index > 0 { line.append(NSAttributedString(string: gap, attributes: [.font: font])) }
            line.append(NSAttributedString(string: hint.keys + " " + hint.action,
                                           attributes: [.font: font, .foregroundColor: hint.color]))
        }
        return line
    }
}
