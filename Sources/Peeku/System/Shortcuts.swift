import AppKit
import Observation
import PeekuKit

/// The user's global shortcuts, which Settings edits and every label reads, so a change shows
/// everywhere at once. Recording a new one happens here too: the notch's key handler hands
/// keys over while a row in Settings is listening.
@MainActor
@Observable
final class Shortcuts {
    static let shared = Shortcuts()

    /// Each action's shortcut; an action the user cleared has none.
    private(set) var active: [ShortcutAction: Shortcut] = [:]
    /// Actions whose shortcut another app already holds, so it does nothing.
    var unavailable: Set<ShortcutAction> = []
    /// The action whose Settings row is waiting for keys. Hotkeys are off meanwhile, so
    /// pressing the current combination records it instead of running it.
    private(set) var recording: ShortcutAction?
    /// Why the last keys pressed while recording weren't taken.
    private(set) var recordingError: String?

    /// Called whenever the shortcuts or recording change, so the app registers them again.
    @ObservationIgnored var onChange: (() -> Void)?

    private init() { reload() }

    func label(_ action: ShortcutAction) -> String? { active[action]?.label }

    func set(_ shortcut: Shortcut?, for action: ShortcutAction) {
        Preferences.setShortcut(shortcut, for: action)
        reload()
        onChange?()
    }

    func resetToDefaults() {
        Preferences.resetShortcuts()
        recording = nil
        reload()
        onChange?()
    }

    func startRecording(_ action: ShortcutAction) {
        recording = action
        recordingError = nil
        onChange?()
    }

    func stopRecording() {
        guard recording != nil else { return }
        recording = nil
        recordingError = nil
        onChange?()
    }

    /// Takes a key pressed while recording. Esc cancels, Delete clears the shortcut, and
    /// anything else becomes the shortcut when it has ⌘, ⌥ or ⌃ and isn't taken.
    func record(_ event: NSEvent) {
        guard let action = recording else { return }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: Shortcut.Modifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        let code = Int(event.keyCode)
        if modifiers.isEmpty, code == 0x35 { return stopRecording() }
        if modifiers.isEmpty, code == 0x33 || code == 0x75 {
            recording = nil
            return set(nil, for: action)
        }
        let key = Shortcut.specialKey(code) ?? event.charactersIgnoringModifiers?.uppercased() ?? ""
        let shortcut = Shortcut(keyCode: code, modifiers: modifiers, key: key)
        guard !key.isEmpty, shortcut.isUsable else {
            recordingError = "Use ⌘, ⌥ or ⌃ with a key."
            return
        }
        if let other = ShortcutAction.conflict(for: shortcut, excluding: action, in: active) {
            recordingError = "\(shortcut.label) is already \(other.title)."
            return
        }
        recording = nil
        recordingError = nil
        set(shortcut, for: action)
    }

    private func reload() {
        active = Dictionary(uniqueKeysWithValues: ShortcutAction.allCases.compactMap { action in
            Preferences.shortcut(for: action).map { (action, $0) }
        })
    }
}

extension Shortcut {
    /// The key as a menu item's key equivalent, when a menu can show it.
    var menuKeyEquivalent: String? {
        let arrows = [0x7B: NSLeftArrowFunctionKey, 0x7C: NSRightArrowFunctionKey, 0x7D: NSDownArrowFunctionKey, 0x7E: NSUpArrowFunctionKey]
        if let arrow = arrows[keyCode], let scalar = UnicodeScalar(arrow) { return String(Character(scalar)) }
        guard Shortcut.specialKey(keyCode) == nil, key.count == 1 else { return nil }
        return key.lowercased()
    }

    var eventModifiers: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers.contains(.command) { flags.insert(.command) }
        if modifiers.contains(.option) { flags.insert(.option) }
        if modifiers.contains(.control) { flags.insert(.control) }
        if modifiers.contains(.shift) { flags.insert(.shift) }
        return flags
    }
}
