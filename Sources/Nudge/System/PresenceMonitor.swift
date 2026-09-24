import AppKit
import Darwin
import Observation

/// Knows when Nudge should stay out of the way: the menu bar is hidden (a full-screen app, or
/// auto-hide), the screen is being shared, or the user asked for quiet.
@MainActor
@Observable
final class PresenceMonitor {
    struct State: Equatable {
        var menuBarHidden = false
        var screenSharing = false
        var quiet = false

        /// Reduce Nudge to a glow on the top edge.
        var minimal: Bool { menuBarHidden }
        /// Don't expand the notch on its own.
        var muted: Bool { menuBarHidden || screenSharing || quiet }
    }

    var state = State()
    @ObservationIgnored var onChange: ((State) -> Void)?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastRefresh = Date.distantPast

    /// Helper processes that run only while an app shares the screen. Zoom's `CptHost` is the
    /// reliable one; macOS has no public "screen is being shared" signal.
    static let sharingProcesses: Set<String> = ["CptHost"]

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshSoon() }
            })
        }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refresh()
    }

    /// Full-screen switches animate, so look again once they settle.
    func refreshSoon() {
        refresh()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    /// For pointer moves near the top edge, where the hidden menu bar slides in. Throttled.
    func refreshIfStale() {
        guard Date().timeIntervalSince(lastRefresh) > 0.25 else { return }
        refresh()
    }

    func refresh() {
        lastRefresh = Date()
        var next = State()
        next.menuBarHidden = NotchGeometry.preferredScreen().map { !Self.menuBarVisible(on: $0) } ?? false
        next.screenSharing = Self.anyProcessRunning(Self.sharingProcesses)
        next.quiet = Preferences.quietUntil.map { $0 > Date() } ?? false
        guard next != state else { return }
        state = next
        onChange?(next)
    }

    // MARK: Signals

    /// The menu bar is a window-server window at the main-menu level along the top of the screen.
    /// Window bounds and owners need no permission.
    static func menuBarVisible(on screen: NSScreen) -> Bool {
        guard let primary = NSScreen.screens.first,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return true }
        let top = primary.frame.maxY - screen.frame.maxY
        return windows.contains { window in
            guard (window[kCGWindowLayer as String] as? Int) == NSWindow.Level.mainMenu.rawValue,
                  (window[kCGWindowOwnerName as String] as? String) == "Window Server",
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds) else { return false }
            return abs(rect.minY - top) < 1 && rect.height > 0 && abs(rect.minX - screen.frame.minX) < 1
        }
    }

    nonisolated static func anyProcessRunning(_ names: Set<String>) -> Bool {
        var pids = [pid_t](repeating: 0, count: 8192)
        let count = Int(proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size)))
        var buffer = [UInt8](repeating: 0, count: 256)
        for pid in pids.prefix(max(0, count)) where pid > 0 {
            let length = Int(proc_name(pid, &buffer, UInt32(buffer.count)))
            guard length > 0 else { continue }
            if names.contains(String(decoding: buffer.prefix(length), as: UTF8.self)) { return true }
        }
        return false
    }
}
