import Foundation
import PeekuKit

/// Per-user settings, kept in UserDefaults.
enum Preferences {
    private static let defaults = UserDefaults.standard

    static var onboardingCompleted: Bool {
        get { defaults.bool(forKey: "onboardingCompleted") }
        set { defaults.set(newValue, forKey: "onboardingCompleted") }
    }

    /// Apps whose sessions Peeku ignores, chosen in onboarding or the menu.
    static var disabledHosts: Set<HostApp> {
        get { Set((defaults.stringArray(forKey: "disabledHosts") ?? []).compactMap(HostApp.init(rawValue:))) }
        set { defaults.set(newValue.map(\.rawValue).sorted(), forKey: "disabledHosts") }
    }

    /// Other apps whose sessions Peeku ignores, by bundle id, with their names so they stay in the
    /// menu to turn back on after their sessions end.
    static var disabledApps: [String: String] {
        get { defaults.dictionary(forKey: "disabledApps") as? [String: String] ?? [:] }
        set { defaults.set(newValue, forKey: "disabledApps") }
    }

    static var hostFilter: HostFilter {
        HostFilter(hiddenHosts: disabledHosts, hiddenApps: Set(disabledApps.keys))
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

    /// Peeku in the notch, or in its menu bar icon even on a Mac with a notch. Macs without a
    /// notch always use the menu bar.
    static var prefersMenuBar: Bool {
        get { defaults.bool(forKey: "prefersMenuBar") }
        set { defaults.set(newValue, forKey: "prefersMenuBar") }
    }

    /// Commands in the manager's footer dock. On by default; turned off in Settings → Utilities.
    static var commandsEnabled: Bool {
        get { defaults.object(forKey: "commandsEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "commandsEnabled") }
    }

    /// Play a sound when a session starts waiting or finishes. On by default; Quiet silences it.
    static var soundsEnabled: Bool {
        get { defaults.object(forKey: "soundsEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "soundsEnabled") }
    }

    /// The usage alerts made in the Usage tab. Claude and Codex at 90% until the user changes them.
    static var usageAlertRules: [UsageAlertRule] {
        get {
            guard let data = defaults.data(forKey: "usageAlertRules"),
                  let rules = try? JSONDecoder().decode([UsageAlertRule].self, from: data) else { return UsageAlertRule.defaults }
            return rules
        }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: "usageAlertRules") }
    }

    /// Usage alerts already opened, so a relaunch doesn't show them again. See `UsageAlerts.handled`.
    static var handledUsageAlerts: [String: Int] {
        get { defaults.dictionary(forKey: "handledUsageAlerts") as? [String: Int] ?? [:] }
        set { defaults.set(newValue, forKey: "handledUsageAlerts") }
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

    /// The built-in apps, then every other app sessions have run in.
    static func watchedApps(others: [OtherApp]) -> [WatchedApp] {
        environments.map(WatchedApp.host) + others.map(WatchedApp.other)
    }

    static func isHidden(_ app: WatchedApp) -> Bool {
        switch app {
        case .host(let host): disabledHosts.contains(host)
        case .other(let other): disabledApps[other.bundleID] != nil
        }
    }

    static func toggle(_ app: WatchedApp) {
        switch app {
        case .host(let host):
            var disabled = disabledHosts
            if disabled.contains(host) { disabled.remove(host) } else { disabled.insert(host) }
            disabledHosts = disabled
        case .other(let other):
            var disabled = disabledApps
            disabled[other.bundleID] = disabled[other.bundleID] == nil ? other.name : nil
            disabledApps = disabled
        }
    }
}

/// An app whose sessions Peeku can watch or ignore: one it knows, or any other it has seen.
enum WatchedApp: Hashable {
    case host(HostApp)
    case other(OtherApp)

    var name: String {
        switch self {
        case .host(let host): host.onboardingName
        case .other(let other): other.name
        }
    }

    var host: HostApp? {
        if case .host(let host) = self { host } else { nil }
    }
}
