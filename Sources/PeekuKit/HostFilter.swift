import Foundation

/// An app outside the built-in four that Peeku has seen a session in, e.g. Warp, or `unidentified`
/// for every session whose app Peeku couldn't tell.
public struct OtherApp: Hashable, Sendable {
    public var bundleID: String
    public var name: String

    public init(bundleID: String, name: String) {
        self.bundleID = bundleID
        self.name = name
    }

    /// Sessions in an app Peeku couldn't identify, such as under tmux, all hide together.
    public static let unidentified = OtherApp(bundleID: "", name: "Other Apps")

    public var isUnidentified: Bool { bundleID.isEmpty }

    /// Apps seen in current sessions or history, plus hidden ones so they can be shown again, by
    /// name, with `unidentified` last. `name` looks up an app the session didn't name.
    public static func seen(sessions: [PeekuSession], history: [HistoryEntry], hidden: [String: String],
                            name lookUp: (String) -> String? = { _ in nil }) -> [OtherApp] {
        var names = hidden
        var anyUnidentified = hidden[unidentified.bundleID] != nil
        func add(_ bundleID: String?, _ name: String?) {
            guard let bundleID, !bundleID.isEmpty, let name = name ?? names[bundleID] ?? lookUp(bundleID) else {
                return anyUnidentified = true
            }
            names[bundleID] = name
        }
        for entry in history where entry.host == .other { add(entry.hostBundleID, entry.hostName) }
        for session in sessions where session.host == .other { add(session.hostBundleID, session.hostAppName) }
        names[unidentified.bundleID] = nil
        let apps = names.map { OtherApp(bundleID: $0.key, name: $0.value) }
            .sorted { ($0.name.localizedLowercase, $0.bundleID) < ($1.name.localizedLowercase, $1.bundleID) }
        return anyUnidentified ? apps + [unidentified] : apps
    }
}

/// Which apps' sessions the user turned off: built-in hosts by type, any other app by bundle id.
public struct HostFilter: Sendable {
    public var hiddenHosts: Set<HostApp>
    public var hiddenApps: Set<String>

    public init(hiddenHosts: Set<HostApp>, hiddenApps: Set<String>) {
        self.hiddenHosts = hiddenHosts
        self.hiddenApps = hiddenApps
    }

    public func hides(_ session: PeekuSession) -> Bool { hides(host: session.host, bundleID: session.hostBundleID) }
    public func hides(_ entry: HistoryEntry) -> Bool { hides(host: entry.host, bundleID: entry.hostBundleID) }

    private func hides(host: HostApp, bundleID: String?) -> Bool {
        if hiddenHosts.contains(host) { return true }
        return host == .other && hiddenApps.contains(bundleID ?? OtherApp.unidentified.bundleID)
    }
}
