import Carbon.HIToolbox
import PeekuKit

/// System-wide shortcuts via Carbon hot keys, which need no Accessibility permission.
final class HotKeys {
    private var handlers: [UInt32: () -> Void] = [:]
    private var references: [EventHotKeyRef] = []
    private var eventHandler: EventHandlerRef?
    private var nextID: UInt32 = 0
    private static let signature: OSType = 0x5049_5021 // "PEEKU!"

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr else { return status }
            let hotKeys = Unmanaged<HotKeys>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { hotKeys.handlers[id.id]?() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
    }

    /// Registers the shortcut. False when it can't be had, usually because another app holds it.
    @discardableResult
    func register(_ shortcut: Shortcut, action: @escaping () -> Void) -> Bool {
        nextID += 1
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(shortcut.keyCode), UInt32(Self.carbon(shortcut.modifiers)),
                                         EventHotKeyID(signature: Self.signature, id: nextID), GetApplicationEventTarget(), 0, &reference)
        guard status == noErr, let reference else { return false }
        handlers[nextID] = action
        references.append(reference)
        return true
    }

    /// Lets go of every shortcut, e.g. before registering the user's new set.
    func unregisterAll() {
        for reference in references { UnregisterEventHotKey(reference) }
        references.removeAll()
        handlers.removeAll()
    }

    private static func carbon(_ modifiers: Shortcut.Modifiers) -> Int {
        (modifiers.contains(.command) ? cmdKey : 0) | (modifiers.contains(.option) ? optionKey : 0)
            | (modifiers.contains(.control) ? controlKey : 0) | (modifiers.contains(.shift) ? shiftKey : 0)
    }
}
