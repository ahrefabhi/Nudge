import AppKit
import ApplicationServices
import PipKit

/// The two macOS permissions Pip uses: Accessibility, to raise the exact window, and
/// Automation, to switch iTerm and Terminal tabs.
enum Permissions {
    static var accessibilityTrusted: Bool { AXIsProcessTrusted() }

    /// Adds Pip to the Accessibility list and shows the system prompt.
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
}
