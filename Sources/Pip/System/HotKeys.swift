import Carbon.HIToolbox

/// System-wide shortcuts via Carbon hot keys, which need no Accessibility permission.
final class HotKeys {
    private var handlers: [UInt32: () -> Void] = [:]
    private var references: [EventHotKeyRef] = []
    private var eventHandler: EventHandlerRef?
    private static let signature: OSType = 0x5049_5021 // "PIP!"

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

    /// `modifiers` uses Carbon masks such as `cmdKey | optionKey`.
    func register(keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        let id = UInt32(handlers.count + 1)
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), EventHotKeyID(signature: Self.signature, id: id),
                                         GetApplicationEventTarget(), 0, &reference)
        guard status == noErr, let reference else { return }
        handlers[id] = action
        references.append(reference)
    }
}
