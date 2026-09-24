import AppKit
import ApplicationServices
import NudgeKit
import SwiftUI

/// After Open Session, outlines the window Nudge just raised: a 2px accent ring that fades in,
/// holds and fades out over 1.4s. The overlay never takes clicks or focus.
final class FocusRing {
    private var panel: NSPanel?
    private var generation = 0

    /// How long to wait for the target app to come to the front.
    private static let activationTimeout: TimeInterval = 1.2
    /// Room around the window for the outer glow.
    private static let glowMargin: CGFloat = 24

    func flash(appBundleID bundleID: String, color: Color) {
        generation += 1
        let current = generation
        waitUntilFrontmost(bundleID, deadline: Date().addingTimeInterval(Self.activationTimeout)) { [weak self] app in
            guard let self, current == self.generation, let app,
                  let frame = Self.frontWindowFrame(of: app.processIdentifier) else { return }
            self.show(around: frame, color: color, generation: current)
        }
    }

    // MARK: Finding the window

    /// Polls until the app is frontmost, then waits a moment for its tab or window to finish switching.
    private func waitUntilFrontmost(_ bundleID: String, deadline: Date, then done: @escaping (NSRunningApplication?) -> Void) {
        if let front = NSWorkspace.shared.frontmostApplication, front.bundleIdentifier == bundleID {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { MainActor.assumeIsolated { done(front) } }
            return
        }
        guard Date() < deadline else { return done(nil) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            MainActor.assumeIsolated { self?.waitUntilFrontmost(bundleID, deadline: deadline, then: done) }
        }
    }

    /// The app's focused window in AppKit coordinates: from Accessibility when Nudge is trusted,
    /// otherwise its frontmost normal window from the window server.
    static func frontWindowFrame(of pid: pid_t) -> CGRect? {
        guard let primary = NSScreen.screens.first else { return nil }
        let topLeft = Permissions.accessibilityTrusted ? focusedWindowFrame(pid) : nil
        guard let rect = topLeft.flatMap({ isWindowSized($0) ? $0 : nil }) ?? frontmostWindowFrame(pid) else { return nil }
        return ScreenGeometry.appKitRect(fromTopLeft: rect, primaryDisplayHeight: primary.frame.height)
    }

    private static func focusedWindowFrame(_ pid: pid_t) -> CGRect? {
        let app = AXUIElementCreateApplication(pid)
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, "AXFocusedWindow" as CFString, &window) == .success,
              let window, CFGetTypeID(window) == AXUIElementGetTypeID() else { return nil }
        let element = window as! AXUIElement
        var position: CFTypeRef?, size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXPosition" as CFString, &position) == .success,
              AXUIElementCopyAttributeValue(element, "AXSize" as CFString, &size) == .success,
              let position, let size,
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero, extent = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &origin),
              AXValueGetValue(size as! AXValue, .cgSize, &extent) else { return nil }
        return CGRect(origin: origin, size: extent)
    }

    /// Window bounds need no permission (only window titles do).
    private static func frontmostWindowFrame(_ pid: pid_t) -> CGRect? {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return nil }
        // The list runs front to back; layer 0 is ordinary app windows. Apps also own thin
        // strips and invisible helpers on that layer, so skip anything that isn't window-sized.
        for window in windows {
            guard (window[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  (window[kCGWindowLayer as String] as? Int) == 0,
                  (window[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds), isWindowSized(rect) else { continue }
            return rect
        }
        return nil
    }

    private static func isWindowSized(_ rect: CGRect) -> Bool { rect.width > 160 && rect.height > 120 }

    // MARK: Overlay

    private func show(around frame: CGRect, color: Color, generation current: Int) {
        panel?.orderOut(nil)
        let panel = NSPanel(contentRect: frame.insetBy(dx: -Self.glowMargin, dy: -Self.glowMargin),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.animationBehavior = .none
        panel.collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary, .canJoinAllSpaces]
        panel.contentView = NSHostingView(rootView: FocusRingView(color: color, margin: Self.glowMargin))
        panel.orderFrontRegardless()
        self.panel = panel

        DispatchQueue.main.asyncAfter(deadline: .now() + FocusRingView.duration + 0.05) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, current == self.generation else { return }
                self.panel?.orderOut(nil)
                self.panel = nil
            }
        }
    }
}

/// The ring itself: `box-shadow: 0 0 0 2px accent/.8, 0 0 24px accent/.25`, inset 6px, radius 10.
struct FocusRingView: View {
    static let duration: TimeInterval = 1.4
    private static let opacity = Keyframes(.ease, [(0, 0), (0.15, 1), (0.70, 1), (1, 0)])

    let color: Color
    let margin: CGFloat
    /// Snapshots render the held, fully visible state.
    @Environment(\.nudgeStill) private var still
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation(paused: still)) { context in
            let progress = still ? 0.5 : min(1, context.date.timeIntervalSince(start) / Self.duration)
            let ring = RoundedRectangle(cornerRadius: 10, style: .continuous)
            ring
                .stroke(color.opacity(0.8), lineWidth: 2)
                .shadow(color: color.opacity(0.25), radius: 12)
                .padding(margin + 6)
                .opacity(Self.opacity.value(at: progress))
        }
        .allowsHitTesting(false)
    }
}
