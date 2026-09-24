import ServiceManagement

/// Opening Nudge at login, through macOS's Login Items.
enum LoginItem {
    enum Status: Equatable {
        case on, off
        /// Registered, but the user must allow it in System Settings → Login Items.
        case needsApproval
        /// Not running from an app bundle (e.g. `swift run`), so macOS can't register it.
        case unavailable
    }

    static var status: Status {
        switch SMAppService.mainApp.status {
        case .enabled: .on
        case .requiresApproval: .needsApproval
        case .notRegistered: .off
        case .notFound: .unavailable
        @unknown default: .unavailable
        }
    }

    static func set(_ on: Bool) throws {
        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }

    static func openSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
