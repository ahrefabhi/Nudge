import AppKit
import Darwin
import NudgeKit

/// Brings the app, tab or window that holds a session to the front. It never types into it.
enum SessionOpener {
    enum Failure: Error, CustomStringConvertible {
        case appNotRunning(String)
        case tabNotFound(String)
        case automationDenied(String)

        var description: String {
            switch self {
            case .appNotRunning(let app): "\(app) isn't running."
            case .tabNotFound(let app): "Couldn't find the session's tab in \(app)."
            case .automationDenied(let app): "Allow Nudge to control \(app) in System Settings → Privacy & Security → Automation."
            }
        }
    }

    static func open(_ session: NudgeSession, observed: ObservedSession?) -> Result<Void, Failure> {
        switch session.host {
        case .iTerm:
            if let guid = observed.flatMap(SessionProjection.itermSessionGUID) {
                return run(ItermScript.selectSession(id: guid), app: "iTerm")
            }
            if let tty = observed?.pid.flatMap(terminalDevice) { return run(ItermScript.selectSession(tty: tty), app: "iTerm") }
            return activate(bundleID: "com.googlecode.iterm2", name: "iTerm")
        case .terminal:
            if let tty = observed?.pid.flatMap(terminalDevice) { return run(TerminalScript.selectTab(tty: tty), app: "Terminal") }
            return activate(bundleID: "com.apple.Terminal", name: "Terminal")
        case .vsCode:
            return openFolder(observed?.cwd, bundleID: observed?.host.resolvedBundleID ?? "com.microsoft.VSCode", name: "VS Code")
        case .claude:
            return activate(bundleID: "com.anthropic.claudefordesktop", name: "Claude")
        case .other:
            // Any other terminal or editor: the app, then its window by title when Accessibility allows.
            guard let observed, let app = HostWindows.application(for: observed) else {
                return .failure(.appNotRunning(observed?.host.appName ?? "The session's app"))
            }
            HostWindows.raise(observed, in: app)
            app.unhide()
            app.activate()
            return .success(())
        }
    }

    // MARK: Apps

    private static func activate(bundleID: String, name: String) -> Result<Void, Failure> {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            return .failure(.appNotRunning(name))
        }
        app.unhide()
        app.activate()
        return .success(())
    }

    /// VS Code focuses the window that already has this folder open.
    private static func openFolder(_ path: String?, bundleID: String, name: String) -> Result<Void, Failure> {
        guard let path, !path.isEmpty, let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return activate(bundleID: bundleID, name: name)
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open([URL(filePath: path, directoryHint: .isDirectory)], withApplicationAt: appURL, configuration: configuration)
        return .success(())
    }

    private static func run(_ source: String, app: String) -> Result<Void, Failure> {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            // -1743: the user hasn't allowed Nudge to send Apple Events to this app.
            let code = error[NSAppleScript.errorNumber] as? Int
            return .failure(code == -1743 ? .automationDenied(app) : .tabNotFound(app))
        }
        return result?.stringValue == "focused" ? .success(()) : .failure(.tabNotFound(app))
    }

    // MARK: Terminal device

    /// The session process's controlling terminal, e.g. "/dev/ttys004".
    static func terminalDevice(pid: Int32) -> String? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size, info.e_tdev != UInt32.max,
              let name = devname(dev_t(bitPattern: info.e_tdev), S_IFCHR) else { return nil }
        let device = String(cString: name)
        return device.wholeMatch(of: /ttys?\d+/) == nil ? nil : "/dev/\(device)"
    }
}

/// Scripts receive only validated identifiers (a GUID or a /dev/ttys path), never session text.
private enum ItermScript {
    static func selectSession(id: String) -> String { script(matching: "id of hostSession is \"\(id)\"") }
    static func selectSession(tty: String) -> String { script(matching: "tty of hostSession is \"\(tty)\"") }

    private static func script(matching condition: String) -> String {
        """
        tell application id "com.googlecode.iterm2"
          repeat with hostWindow in windows
            repeat with hostTab in tabs of hostWindow
              repeat with hostSession in sessions of hostTab
                if \(condition) then
                  set miniaturized of hostWindow to false
                  select hostWindow
                  select hostTab
                  select hostSession
                  activate
                  return "focused"
                end if
              end repeat
            end repeat
          end repeat
        end tell
        return "missing"
        """
    }
}

private enum TerminalScript {
    static func selectTab(tty: String) -> String {
        """
        tell application id "com.apple.Terminal"
          repeat with hostWindow in windows
            repeat with hostTab in tabs of hostWindow
              if tty of hostTab is "\(tty)" then
                set selected of hostTab to true
                set miniaturized of hostWindow to false
                set index of hostWindow to 1
                activate
                return "focused"
              end if
            end repeat
          end repeat
        end tell
        return "missing"
        """
    }
}
