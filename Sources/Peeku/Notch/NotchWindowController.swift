import AppKit
import Carbon.HIToolbox
import PeekuKit
import SwiftUI

/// Keeps the panel pinned to the notch and routes the pointer and keyboard to the island.
final class NotchWindowController {
    /// Room around the largest island for its shadow.
    private static let canvas = CGSize(width: 600, height: 720)

    let panel: NotchPanel
    private let machine: PhaseMachine
    private let presence: PresenceMonitor?
    private let commands: CommandRunner?
    private let hitArea = IslandHitArea()
    private let hosting: FirstClickHostingView<IslandView>
    private var notch = NotchGeometry.fallback
    private var screen: NSScreen?
    private var monitors: [Any] = []
    private var screenObserver: NSObjectProtocol?

    init(machine: PhaseMachine, presence: PresenceMonitor? = nil, commands: CommandRunner? = nil) {
        self.machine = machine
        self.presence = presence
        self.commands = commands
        panel = NotchPanel(contentRect: NSRect(origin: .zero, size: Self.canvas))
        hosting = FirstClickHostingView(rootView: IslandView(machine: machine, notch: .fallback, presence: presence, commands: commands, hitArea: hitArea))
        hosting.sizingOptions = []
        panel.contentView = hosting

        placeOnPreferredScreen()
        installMonitors()
        observeMachine()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.placeOnPreferredScreen() }
        }
    }

    func show() {
        panel.orderFrontRegardless()
    }

    /// Takes keyboard focus without activating Peeku, e.g. for the ⌥⌘. shortcut.
    func focusIsland() {
        panel.makeKey()
    }

    // MARK: Placement

    private func placeOnPreferredScreen() {
        guard let screen = NotchGeometry.preferredScreen() else { return }
        self.screen = screen
        notch = NotchGeometry(screen: screen)
        hosting.rootView = IslandView(machine: machine, notch: notch, presence: presence, commands: commands, hitArea: hitArea)
        let frame = screen.frame
        panel.setFrame(NSRect(x: frame.midX - Self.canvas.width / 2, y: frame.maxY - Self.canvas.height,
                              width: Self.canvas.width, height: Self.canvas.height), display: true)
    }

    /// What takes clicks, in screen coordinates: the island, or in light mode the notch, the
    /// hanging Peeku and the panel below it.
    private var islandRect: NSRect {
        guard let screen else { return .zero }
        let top = screen.frame.maxY, midX = screen.frame.midX
        let metrics = IslandMetrics.make(for: machine, notch: notch, minimal: presence?.state.minimal ?? false)
        let systemIsDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if !metrics.glow, PanelAppearance.stored.isLight(systemIsDark: systemIsDark),
           let panel = LightPanelLayout.make(for: machine, notch: notch) {
            // Alerts size to their content; until the panel has measured itself, assume the design height.
            let bottom = panel.top + (panel.fitsContent ? hitArea.lightPanelHeight ?? panel.height : panel.height)
            return NSRect(x: midX - panel.width / 2, y: top - bottom, width: panel.width, height: bottom)
        }
        return NSRect(x: midX - metrics.outerWidth / 2, y: top - metrics.height, width: metrics.outerWidth, height: metrics.height)
    }

    // MARK: Pointer and keys

    private func installMonitors() {
        // AppKit delivers monitor callbacks on the main thread.
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown], handler: { [weak self] event in
            self?.handleGlobal(event)
        }) { monitors.append(global) }

        if let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .keyDown], handler: { [weak self] event in
            self?.handleLocal(event) ?? event
        }) { monitors.append(local) }
    }

    private func handleGlobal(_ event: NSEvent) {
        updatePassThrough()
        // A click that reached another app landed outside the island.
        if event.type == .leftMouseDown { machine.tapOutside() }
    }

    private func handleLocal(_ event: NSEvent) -> NSEvent? {
        switch event.type {
        case .mouseMoved:
            updatePassThrough()
            return event
        case .keyDown:
            // Keys typed in Peeku's own windows (Settings, the command editor) are theirs.
            guard event.window === panel else { return event }
            return handleKey(event) ? nil : event
        default:
            return event
        }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        let command = event.modifierFlags.contains(.command)
        switch Int(event.keyCode) {
        case kVK_Return, kVK_ANSI_KeypadEnter:
            guard machine.phase == .alert || machine.phase == .pill else { return false }
            machine.openFocused()
        case kVK_Escape:
            machine.escape()
        default:
            guard command, let digit = event.charactersIgnoringModifiers.flatMap(Int.init), (1...9).contains(digit) else { return false }
            // ⌥⌘. then ⌥⌘1–4, with ⌥⌘ still held, picks a manager tab; ⌘ alone opens a row.
            if event.modifierFlags.contains(.option) { return machine.showTab(digit) }
            machine.openRow(digit)
        }
        return true
    }

    private func updatePassThrough() {
        let pointer = NSEvent.mouseLocation
        // A hidden menu bar slides in when the pointer reaches the top edge; notice it quickly.
        if let screen, pointer.y > screen.frame.maxY - 40 { presence?.refreshIfStale() }
        let inside = islandRect.contains(pointer)
        if panel.ignoresMouseEvents == inside { panel.ignoresMouseEvents = !inside }
    }

    /// Re-checks pass-through and key focus whenever the phase changes under a still pointer.
    private func observeMachine() {
        withObservationTracking {
            _ = machine.phase
            _ = machine.queue.count
            _ = presence?.state
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.updatePassThrough()
                    self.releaseKeyIfQuiet()
                    self.observeMachine()
                }
            }
        }
    }

    /// Give the keyboard back once nothing interactive is showing.
    private func releaseKeyIfQuiet() {
        guard panel.isKeyWindow else { return }
        switch machine.phase {
        case .alert, .manager, .pill: return
        default: panel.resignKey()
        }
    }
}

/// The panel is never key before the user clicks it, and by default that first click only makes
/// it key. Deliver it, so one click opens the island.
final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
