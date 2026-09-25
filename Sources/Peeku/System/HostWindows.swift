import AppKit
import ApplicationServices
import PeekuKit

/// Finds a session's window by title through Accessibility, in any app. Without Accessibility
/// Peeku can still bring the app forward, just not pick the window.
enum HostWindows {
    /// The running app a session belongs to: its recorded main process if that's still the same
    /// app (pids get reused), else any instance of its bundle.
    static func application(for observed: ObservedSession) -> NSRunningApplication? {
        let hint = observed.host
        if let pid = hint.appPID, let app = NSRunningApplication(processIdentifier: pid),
           app.bundleIdentifier != nil, app.bundleIdentifier == hint.appBundleID { return app }
        guard let bundleID = hint.resolvedBundleID else { return nil }
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
    }

    /// Unminimizes and raises the window whose title best matches the session. False when there's
    /// no Accessibility access or no window matches, so the caller just activates the app.
    @discardableResult
    static func raise(_ observed: ObservedSession, in app: NSRunningApplication) -> Bool {
        guard Permissions.accessibilityTrusted else { return false }
        let windows = windows(of: app.processIdentifier)
        guard let index = WindowMatch.best(windows.map(\.title), for: observed) else { return false }
        let window = windows[index].element
        AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        return AXUIElementPerformAction(window, kAXRaiseAction as CFString) == .success
    }

    /// The title of the app's focused window, e.g. "session.ts — payments-api" in VS Code.
    static func focusedTitle(pid: pid_t) -> String? {
        guard Permissions.accessibilityTrusted,
              let window = element(AXUIElementCreateApplication(pid), kAXFocusedWindowAttribute) else { return nil }
        return title(of: window)
    }

    // MARK: Accessibility

    /// The app's windows, roughly front to back.
    private static func windows(of pid: pid_t) -> [(element: AXUIElement, title: String)] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), kAXWindowsAttribute as CFString, &value) == .success,
              let list = value as? [AXUIElement] else { return [] }
        return list.compactMap { window in title(of: window).map { (window, $0) } }
    }

    private static func element(_ parent: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(parent, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func title(of window: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &value) == .success else { return nil }
        return value as? String
    }
}
