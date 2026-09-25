import AppKit
import ApplicationServices
import Darwin
import Observation

/// Knows when Peeku should stay out of the way: the menu bar is hidden (a full-screen app, or
/// auto-hide), the screen is being shared, or the user asked for quiet.
@MainActor
@Observable
final class PresenceMonitor {
    struct State: Equatable {
        var menuBarHidden = false
        var screenSharing = false
        var quiet = false

        /// Reduce Peeku to a glow on the top edge.
        var minimal: Bool { menuBarHidden }
        /// Don't expand the notch on its own.
        var muted: Bool { menuBarHidden || screenSharing || quiet }
    }

    var state = State()
    @ObservationIgnored var onChange: ((State) -> Void)?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastRefresh = Date.distantPast
    /// Read off the main thread, since asking Control Center takes tens of milliseconds.
    @ObservationIgnored private var screenRecording = false
    @ObservationIgnored private let io = DispatchQueue(label: "app.peeku.presence", qos: .utility)

    /// Helper processes that run only while an app shares the screen. Zoom's `CptHost` works
    /// without Accessibility, which the Control Center check needs.
    static let sharingProcesses: Set<String> = ["CptHost"]

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshSoon() }
            })
        }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
                self?.checkScreenRecording()
            }
        }
        checkScreenRecording()
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
        next.screenSharing = screenRecording || Self.anyProcessRunning(Self.sharingProcesses)
        next.quiet = Preferences.quietUntil.map { $0 > Date() } ?? false
        guard next != state else { return }
        state = next
        onChange?(next)
    }

    private func checkScreenRecording() {
        io.async { [weak self] in
            let recording = Self.screenRecordingInUse()
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, recording != self.screenRecording else { return }
                    self.screenRecording = recording
                    self.refresh()
                }
            }
        }
    }

    // MARK: Signals

    /// macOS's own "Screen Recording" label, in the user's language.
    nonisolated static let screenRecordingLabel = Bundle(path: "/System/Library/CoreServices/ControlCenter.app")?
        .localizedString(forKey: "Screen Recording", value: nil, table: "SensorIndicators") ?? "Screen Recording"

    /// Whether any app is capturing the screen (a Meet, Slack, Teams or Zoom share, or a recording).
    /// While one is, macOS's Control Center menu bar item reads e.g. "Control Center, Screen
    /// Recording is in use". Reading it needs Accessibility, which Peeku already asks for.
    nonisolated static func screenRecordingInUse() -> Bool {
        guard AXIsProcessTrusted(),
              let controlCenter = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.controlcenter").first else { return false }
        let app = AXUIElementCreateApplication(controlCenter.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.5)
        guard let bar = attribute(app, kAXExtrasMenuBarAttribute).map({ $0 as! AXUIElement }),
              let items = attribute(bar, kAXChildrenAttribute) as? [AXUIElement],
              let item = items.first(where: { attribute($0, kAXIdentifierAttribute) as? String == "com.apple.menuextra.controlcenter" }),
              let description = attribute(item, kAXDescriptionAttribute) as? String else { return false }
        return description.contains(screenRecordingLabel)
    }

    private nonisolated static func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

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
