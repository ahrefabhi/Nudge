import AppKit
import ApplicationServices
import PeekuKit

/// The two macOS permissions Peeku uses: Accessibility, to raise the exact window, and
/// Automation, to switch iTerm and Terminal tabs.
enum Permissions {
    static var accessibilityTrusted: Bool { AXIsProcessTrusted() }

    /// Adds Peeku to the Accessibility list and shows the system prompt.
    static func requestAccessibility() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    nonisolated enum Automation: Equatable, Sendable {
        case granted, notAsked, denied
        /// macOS can only ask while the target app is running.
        case notRunning
    }

    /// Blocks while the user answers when `ask` is true, so call it off the main thread.
    nonisolated static func automation(bundleID: String, ask: Bool) -> Automation {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty else { return .notRunning }
        guard let target = NSAppleEventDescriptor(bundleIdentifier: bundleID).aeDesc else { return .notAsked }
        switch AEDeterminePermissionToAutomateTarget(target, typeWildCard, typeWildCard, ask) {
        case noErr: return .granted
        case OSStatus(errAEEventNotPermitted): return .denied
        case OSStatus(procNotFound): return .notRunning
        default: return .notAsked
        }
    }

    /// Clears Peeku's own Accessibility and Automation entries, including stale ones an earlier
    /// build left behind (switched on in System Settings, but no longer matching this Peeku).
    /// Only Peeku's bundle ID is touched. Returns whether both resets succeeded.
    @discardableResult
    static func resetPeekuEntries() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        return resetEntries(for: bundleID)
    }

    /// Clears the Accessibility and Automation entries of one bundle ID.
    @discardableResult
    static func resetEntries(for bundleID: String) -> Bool {
        return ["Accessibility", "AppleEvents"].allSatisfy { service in
            let reset = Process()
            reset.executableURL = URL(filePath: "/usr/bin/tccutil")
            reset.arguments = ["reset", service, bundleID]
            reset.standardOutput = FileHandle.nullDevice
            reset.standardError = FileHandle.nullDevice
            guard (try? reset.run()) != nil else { return false }
            reset.waitUntilExit()
            return reset.terminationStatus == 0
        }
    }

    enum Pane: String {
        case accessibility = "Privacy_Accessibility"
        case automation = "Privacy_Automation"
    }

    static func open(_ pane: Pane) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane.rawValue)") {
            NSWorkspace.shared.open(url)
        }
    }
}

extension HostApp {
    var bundleID: String? {
        switch self {
        case .iTerm: "com.googlecode.iterm2"
        case .terminal: "com.apple.Terminal"
        case .vsCode: "com.microsoft.VSCode"
        case .claude: "com.anthropic.claudefordesktop"
        case .other: nil
        }
    }

    /// Tabs in these apps are switched with Apple Events.
    var needsAutomation: Bool { self == .iTerm || self == .terminal }

    var isInstalled: Bool {
        bundleID.map { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil } ?? false
    }

    var isRunning: Bool {
        bundleID.map { !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty } ?? false
    }

    var applicationURL: URL? {
        bundleID.flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
    }

    var icon: NSImage? { applicationURL.map { NSWorkspace.shared.icon(forFile: $0.path) } }

    /// Opens (or brings forward) the app. It never starts Claude or types anything into it.
    func launch() {
        guard let url = applicationURL else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }
}
