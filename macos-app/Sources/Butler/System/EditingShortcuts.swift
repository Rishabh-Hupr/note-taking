import AppKit

/// The standard text-editing shortcuts, defined once. Both the app's Edit menu and
/// the overlay panels are built from this table, so they can't drift apart:
/// add or change a shortcut here and both pick it up.
///
/// Why two consumers: menu key equivalents only fire while the app is active, and
/// Butler's panels are non-activating (they never steal focus from the app you're
/// in), so `OverlayPanel` dispatches these shortcuts itself.
enum EditingShortcuts {
    struct Shortcut {
        let title: String
        let action: Selector
        let key: String                       // what the shortcut types on a Latin layout
        let modifiers: NSEvent.ModifierFlags
        let keyCode: UInt16                   // ANSI key position (kVK_ANSI_*), for non-Latin layouts
        var separatorAfter = false            // Edit-menu grouping only
    }

    static let all: [Shortcut] = [
        Shortcut(title: "Undo", action: Selector(("undo:")), key: "z", modifiers: [.command], keyCode: 6),
        Shortcut(title: "Redo", action: Selector(("redo:")), key: "z", modifiers: [.command, .shift], keyCode: 6,
                 separatorAfter: true),
        Shortcut(title: "Cut", action: #selector(NSText.cut(_:)), key: "x", modifiers: [.command], keyCode: 7),
        Shortcut(title: "Copy", action: #selector(NSText.copy(_:)), key: "c", modifiers: [.command], keyCode: 8),
        Shortcut(title: "Paste", action: #selector(NSText.paste(_:)), key: "v", modifiers: [.command], keyCode: 9),
        Shortcut(title: "Select All", action: #selector(NSText.selectAll(_:)), key: "a", modifiers: [.command], keyCode: 0),
    ]

    /// The Edit menu, built from `all`.
    static func makeEditMenu() -> NSMenu {
        let menu = NSMenu(title: "Edit")
        for shortcut in all {
            let item = NSMenuItem(title: shortcut.title, action: shortcut.action, keyEquivalent: shortcut.key)
            item.keyEquivalentModifierMask = shortcut.modifiers
            menu.addItem(item)
            if shortcut.separatorAfter { menu.addItem(.separator()) }
        }
        return menu
    }

    /// The action for a key event, if it's one of `all`. Matches the typed letter;
    /// on non-Latin layouts (Russian, Greek, Hebrew…) ⌘V types e.g. "м", so it falls
    /// back to the physical key position. Caps Lock and similar flags are ignored.
    static func action(for event: NSEvent) -> Selector? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])
        let typed = event.charactersIgnoringModifiers?.lowercased()
        let isLatin = typed?.count == 1 && typed?.first?.isASCII == true
        return all.first { shortcut in
            shortcut.modifiers == flags && (isLatin ? typed == shortcut.key : event.keyCode == shortcut.keyCode)
        }?.action
    }
}
