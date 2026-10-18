import AppKit
import Testing
@testable import Butler

@Suite struct EditingShortcutTests {
    private func key(_ chars: String, _ flags: NSEvent.ModifierFlags, keyCode: UInt16 = 0) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                         windowNumber: 0, context: nil, characters: chars,
                         charactersIgnoringModifiers: chars, isARepeat: false, keyCode: keyCode)!
    }

    @Test func nonLatinLayoutFallsBackToThePhysicalKey() {
        // Russian layout: the V key types "м", C types "с" — still paste / copy.
        #expect(EditingShortcuts.action(for: key("м", [.command], keyCode: 9)) == #selector(NSText.paste(_:)))
        #expect(EditingShortcuts.action(for: key("с", [.command], keyCode: 8)) == #selector(NSText.copy(_:)))
    }

    @Test(arguments: [
        ("x", "cut:"), ("c", "copy:"), ("v", "paste:"), ("a", "selectAll:"), ("z", "undo:"),
    ])
    func commandShortcuts(char: String, selector: String) {
        #expect(EditingShortcuts.action(for: key(char, [.command])) == Selector((selector)))
    }

    @Test func shiftCommandZIsRedo() {
        #expect(EditingShortcuts.action(for: key("z", [.command, .shift])) == Selector(("redo:")))
    }

    @Test func capsLockDoesNotBreakShortcuts() {
        #expect(EditingShortcuts.action(for: key("c", [.command, .capsLock])) == #selector(NSText.copy(_:)))
    }

    @Test func editMenuIsBuiltFromTheSameTable() {
        // Every shortcut the panels handle is in the Edit menu with the same key,
        // modifiers and action — they can't drift apart.
        let items = EditingShortcuts.makeEditMenu().items.filter { !$0.isSeparatorItem }
        #expect(items.count == EditingShortcuts.all.count)
        for (item, shortcut) in zip(items, EditingShortcuts.all) {
            #expect(item.action == shortcut.action)
            #expect(item.keyEquivalent == shortcut.key)
            #expect(item.keyEquivalentModifierMask == shortcut.modifiers)
        }
    }

    @Test func otherKeysAreLeftAlone() {
        #expect(EditingShortcuts.action(for: key("d", [.command])) == nil)     // ⌘D = delete, handled elsewhere
        #expect(EditingShortcuts.action(for: key("c", [.command, .option])) == nil)
        #expect(EditingShortcuts.action(for: key("c", [])) == nil)
    }
}
