import Foundation
import PipKit

/// Per-user settings, kept in UserDefaults.
enum Preferences {
    private static let defaults = UserDefaults.standard

    static var onboardingCompleted: Bool {
        get { defaults.bool(forKey: "onboardingCompleted") }
        set { defaults.set(newValue, forKey: "onboardingCompleted") }
    }

    /// Apps whose sessions Pip ignores, chosen in onboarding or the menu.
    static var disabledHosts: Set<HostApp> {
        get { Set((defaults.stringArray(forKey: "disabledHosts") ?? []).compactMap(HostApp.init(rawValue:))) }
        set { defaults.set(newValue.map(\.rawValue).sorted(), forKey: "disabledHosts") }
    }

    /// Quiet mode: no pop-ups until this time. The count still updates.
    static var quietUntil: Date? {
        get { defaults.object(forKey: "quietUntil") as? Date }
        set { defaults.set(newValue, forKey: "quietUntil") }
    }

    /// Fold an unanswered alert to the pill after 8s. On by default, as in the design.
    static var autoCollapse: Bool {
        get { defaults.object(forKey: "autoCollapse") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "autoCollapse") }
    }

    /// Expand the notch when a session finishes, instead of a 3s wink. Off by default.
    static var popUpOnFinish: Bool {
        get { defaults.bool(forKey: "popUpOnFinish") }
        set { defaults.set(newValue, forKey: "popUpOnFinish") }
    }

    /// Stay quiet for a session whose tab or window is already in front. On by default.
    static var quietInView: Bool {
        get { defaults.object(forKey: "quietInView") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "quietInView") }
    }

    /// Play a sound when a session starts waiting or finishes. On by default; Quiet silences it.
    static var soundsEnabled: Bool {
        get { defaults.object(forKey: "soundsEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "soundsEnabled") }
    }

    /// The system sound for each chime, or nil for none.
    static func sound(for chime: Chime) -> String? {
        guard let name = defaults.string(forKey: "sound.\(chime.rawValue)") else { return chime.defaultSound }
        return name.isEmpty ? nil : name
    }

    static func setSound(_ name: String?, for chime: Chime) {
        defaults.set(name ?? "", forKey: "sound.\(chime.rawValue)")
    }

    /// The apps shown in onboarding and the Environments menu.
    static let environments: [HostApp] = [.iTerm, .terminal, .vsCode, .claude]
}
