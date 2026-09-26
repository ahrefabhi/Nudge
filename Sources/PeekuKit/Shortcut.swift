import Foundation

/// A system-wide key combination, like ⌥⌘, for the agents. Stored as a virtual key code plus
/// modifiers, with the key's label captured when it was recorded, since a key code alone
/// doesn't say what the key prints on this keyboard layout.
public struct Shortcut: Codable, Hashable, Sendable {
    public struct Modifiers: OptionSet, Codable, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let control = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let shift = Modifiers(rawValue: 1 << 2)
        public static let command = Modifiers(rawValue: 1 << 3)

        /// "⌃⌥⇧⌘", in the order macOS menus use.
        public var symbols: String {
            (contains(.control) ? "⌃" : "") + (contains(.option) ? "⌥" : "")
                + (contains(.shift) ? "⇧" : "") + (contains(.command) ? "⌘" : "")
        }
    }

    public var keyCode: Int
    public var modifiers: Modifiers
    /// What the key shows, e.g. "," or "↓".
    public var key: String

    public init(keyCode: Int, modifiers: Modifiers, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.key = key
    }

    /// "⌥⌘,".
    public var label: String { modifiers.symbols + key }

    /// A global shortcut needs ⌘, ⌥ or ⌃; Shift alone would take a key away from typing.
    public var isUsable: Bool { !modifiers.intersection([.command, .option, .control]).isEmpty }

    /// The label for special keys, which print nothing useful. Codes are macOS virtual key codes.
    public static func specialKey(_ keyCode: Int) -> String? {
        switch keyCode {
        case 0x24, 0x4C: "↩"
        case 0x30: "⇥"
        case 0x31: "Space"
        case 0x33: "⌫"
        case 0x75: "⌦"
        case 0x35: "⎋"
        case 0x7B: "←"
        case 0x7C: "→"
        case 0x7D: "↓"
        case 0x7E: "↑"
        case 0x73: "↖"
        case 0x77: "↘"
        case 0x74: "⇞"
        case 0x79: "⇟"
        case 0x7A: "F1"
        case 0x78: "F2"
        case 0x63: "F3"
        case 0x76: "F4"
        case 0x60: "F5"
        case 0x61: "F6"
        case 0x62: "F7"
        case 0x64: "F8"
        case 0x65: "F9"
        case 0x6D: "F10"
        case 0x67: "F11"
        case 0x6F: "F12"
        default: nil
        }
    }
}

/// What a global shortcut does.
public enum ShortcutAction: String, CaseIterable, Codable, Sendable {
    case agents, commands, skills, nextWaiting

    public var title: String {
        switch self {
        case .agents: "Agents"
        case .commands: "Commands"
        case .skills: "Skills"
        case .nextWaiting: "Next waiting agent"
        }
    }

    /// ⌥⌘, for the agents, ⌥⌘. for Commands, ⌥⌘/ for Skills and ⌥⌘↓ for the next waiting agent.
    public var defaultShortcut: Shortcut {
        switch self {
        case .agents: Shortcut(keyCode: 0x2B, modifiers: [.option, .command], key: ",")
        case .commands: Shortcut(keyCode: 0x2F, modifiers: [.option, .command], key: ".")
        case .skills: Shortcut(keyCode: 0x2C, modifiers: [.option, .command], key: "/")
        case .nextWaiting: Shortcut(keyCode: 0x7D, modifiers: [.option, .command], key: "↓")
        }
    }

    /// Another action already using `shortcut` among the active ones, if any. Only the key and modifiers count.
    public static func conflict(for shortcut: Shortcut, excluding action: ShortcutAction,
                                in active: [ShortcutAction: Shortcut]) -> ShortcutAction? {
        allCases.first { other in
            guard other != action, let existing = active[other] else { return false }
            return existing.keyCode == shortcut.keyCode && existing.modifiers == shortcut.modifiers
        }
    }
}
