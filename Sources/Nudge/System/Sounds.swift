import AppKit
import NudgeKit

/// Plays macOS's built-in alert sounds for each chime.
@MainActor
enum Sounds {
    /// The sounds in /System/Library/Sounds, which NSSound finds by name.
    static let names = ["Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero", "Morse", "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink"]

    static func play(_ chime: Chime) {
        guard Preferences.soundsEnabled, let name = Preferences.sound(for: chime) else { return }
        preview(name)
    }

    /// Plays a sound from the start, even if it is still playing.
    static func preview(_ name: String) {
        guard let sound = cache[name] ?? NSSound(named: name) else { return }
        cache[name] = sound
        sound.stop()
        sound.play()
    }

    private static var cache: [String: NSSound] = [:]
}

extension Chime {
    var defaultSound: String {
        switch self {
        case .permission: "Glass"
        case .question: "Pop"
        case .error: "Basso"
        case .finished: "Hero"
        case .usage: "Purr"
        }
    }

    var title: String {
        switch self {
        case .permission: "Needs permission"
        case .question: "Has a question"
        case .error: "Blocked by an error"
        case .finished: "Finished"
        case .usage: "Near a usage limit"
        }
    }
}
