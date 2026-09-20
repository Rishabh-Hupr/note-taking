import AppKit
import Carbon.HIToolbox

// GlobalHotKey registers a system-wide hotkey via Carbon RegisterEventHotKey.
// Carbon hotkeys are truly global and, unlike CGEventTap, need no Accessibility
// permission. The registration lives as long as this object (and the process).
final class GlobalHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let id: UInt32

    // Callbacks keyed by hotkey id, looked up from the C event handler.
    private static var registry: [UInt32: () -> Void] = [:]
    private static var nextID: UInt32 = 1

    /// keyCode/modifiers use Carbon values, e.g. kVK_Space and (cmdKey | optionKey).
    init?(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        self.id = GlobalHotKey.nextID
        GlobalHotKey.nextID += 1
        GlobalHotKey.registry[id] = handler

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let callback: EventHandlerUPP = { _, event, _ -> OSStatus in
            var firedID = EventHotKeyID()
            GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &firedID
            )
            GlobalHotKey.registry[firedID.id]?()
            return noErr
        }

        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &eventType, nil, &eventHandler)

        let hotKeyID = EventHotKeyID(signature: OSType(0x42544C52), id: id) // 'BTLR'
        let status = RegisterEventHotKey(
            keyCode, modifiers, hotKeyID,
            GetApplicationEventTarget(), 0, &hotKeyRef
        )
        if status != noErr { return nil }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
        GlobalHotKey.registry[id] = nil
    }
}
