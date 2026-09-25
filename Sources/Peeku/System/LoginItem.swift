import ServiceManagement

/// Opening Peeku at login, through macOS's Login Items.
enum LoginItem {
    enum Status: Equatable {
        case on, off
        /// Registered, but the user must allow it in System Settings → Login Items.
        case needsApproval
        /// Not running from an app bundle (e.g. `swift run`), so macOS can't register it.
        case unavailable
    }

    static var status: Status {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return .unavailable }
        switch SMAppService.mainApp.status {
        case .enabled: return .on
        case .requiresApproval: return .needsApproval
        // A real app that has never registered also reports `.notFound`, so it can still be turned on.
        case .notRegistered, .notFound: return .off
        @unknown default: return .off
        }
    }

    static func set(_ on: Bool) throws {
        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }

    static func openSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
