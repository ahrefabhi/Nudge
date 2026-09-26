import Foundation
import Testing
@testable import PeekuKit

@Suite struct ShortcutTests {
    @Test func defaultsAreTheOnesInTheReadme() {
        #expect(ShortcutAction.agents.defaultShortcut.label == "⌥⌘,")
        #expect(ShortcutAction.commands.defaultShortcut.label == "⌥⌘.")
        #expect(ShortcutAction.skills.defaultShortcut.label == "⌥⌘/")
        #expect(ShortcutAction.nextWaiting.defaultShortcut.label == "⌥⌘↓")
        let codes = ShortcutAction.allCases.map(\.defaultShortcut.keyCode)
        #expect(Set(codes).count == codes.count)
    }

    @Test func labelsFollowMenuOrder() {
        let shortcut = Shortcut(keyCode: 0x28, modifiers: [.command, .shift, .control, .option], key: "K")
        #expect(shortcut.label == "⌃⌥⇧⌘K")
    }

    @Test func aShortcutNeedsCommandOptionOrControl() {
        #expect(!Shortcut(keyCode: 0x28, modifiers: [], key: "K").isUsable)
        #expect(!Shortcut(keyCode: 0x28, modifiers: [.shift], key: "K").isUsable)
        #expect(Shortcut(keyCode: 0x28, modifiers: [.control], key: "K").isUsable)
    }

    @Test func conflictsIgnoreTheLabelAndTheActionItself() {
        let active = Dictionary(uniqueKeysWithValues: ShortcutAction.allCases.map { ($0, $0.defaultShortcut) })
        let comma = Shortcut(keyCode: 0x2B, modifiers: [.option, .command], key: "<")
        #expect(ShortcutAction.conflict(for: comma, excluding: .skills, in: active) == .agents)
        #expect(ShortcutAction.conflict(for: comma, excluding: .agents, in: active) == nil)
        let shifted = Shortcut(keyCode: 0x2B, modifiers: [.option, .command, .shift], key: "<")
        #expect(ShortcutAction.conflict(for: shifted, excluding: .skills, in: active) == nil)
        var cleared = active
        cleared[.agents] = nil
        #expect(ShortcutAction.conflict(for: comma, excluding: .skills, in: cleared) == nil)
    }

    @Test func shortcutsRoundTrip() throws {
        let shortcut = Shortcut(keyCode: 0x7D, modifiers: [.option, .command], key: "↓")
        let decoded = try JSONDecoder().decode(Shortcut.self, from: JSONEncoder().encode(shortcut))
        #expect(decoded == shortcut)
        #expect(Shortcut.specialKey(0x7D) == "↓")
        #expect(Shortcut.specialKey(0x2B) == nil)
    }
}
