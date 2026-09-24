import AppKit
import ApplicationServices
import NudgeKit

/// Whether the user is already looking at a session: its app is in front, down to the exact
/// tab or window where Nudge can tell, and they've touched the Mac recently. Anything it can't
/// confirm counts as not in view, so Nudge notifies.
@MainActor
enum ForegroundSession {
    /// No keyboard or mouse input for this long means the user has probably stepped away.
    static let idleLimit: TimeInterval = 60

    static func isInView(_ session: NudgeSession, observed: ObservedSession?) -> Bool {
        guard let front = NSWorkspace.shared.frontmostApplication,
              let bundleID = observed?.host.resolvedBundleID ?? session.host.bundleID,
              front.bundleIdentifier == bundleID,
              secondsSinceInput < idleLimit else { return false }
        switch session.host {
        case .iTerm:
            guard automationGranted(bundleID) else { return false }
            let front = runScript(ItermFront.script)?.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard let front, front.count == 2 else { return false }
            if let guid = observed.flatMap(SessionProjection.itermSessionGUID) { return front[0] == guid }
            if let tty = observed?.pid.flatMap(SessionOpener.terminalDevice) { return front[1] == tty }
            return false
        case .terminal:
            guard automationGranted(bundleID), let tty = observed?.pid.flatMap(SessionOpener.terminalDevice) else { return false }
            return runScript(TerminalFront.script) == tty
        case .vsCode, .other:
            // Editors and most terminals title the window with the folder or the program's title.
            guard let observed, let title = HostWindows.focusedTitle(pid: front.processIdentifier) else { return false }
            return WindowMatch.score(title, for: observed) > 0
        case .claude:
            // No way to tell which conversation is showing, so the app being in front is enough.
            return true
        }
    }

    // MARK: Signals

    private static var secondsSinceInput: TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }

    /// Never prompts: asking mid-alert would be worse than notifying.
    private static func automationGranted(_ bundleID: String) -> Bool {
        Permissions.automation(bundleID: bundleID, ask: false) == .granted
    }

    private static func runScript(_ source: String) -> String? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        return error == nil ? result?.stringValue : nil
    }
}

/// Returns "<session id>|<tty>" for iTerm's front session.
private enum ItermFront {
    static let script = """
        tell application id "com.googlecode.iterm2"
          set frontSession to current session of current window
          return (id of frontSession) & "|" & (tty of frontSession)
        end tell
        """
}

private enum TerminalFront {
    static let script = """
        tell application id "com.apple.Terminal"
          return tty of selected tab of front window
        end tell
        """
}
