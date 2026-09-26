import AppKit
import Carbon.HIToolbox
import PeekuKit
import SwiftUI

/// Keeps the panel pinned to the notch and routes the pointer and keyboard to the island. On a
/// Mac without a notch, it pins the panel under the menu bar icon instead.
final class NotchWindowController {
    /// Room around the largest island for its shadow.
    private static let canvas = CGSize(width: 600, height: 720)

    let panel: NotchPanel
    private let machine: PhaseMachine
    private let presence: PresenceMonitor?
    private let commands: CommandRunner?
    private let settings: SettingsModel?
    /// The menu bar icon's frame on screen, for Macs without a notch.
    private let anchor: () -> NSRect?
    private let hitArea = IslandHitArea()
    private let hosting: FirstClickHostingView<IslandView>
    private var notch = NotchGeometry.fallback
    private var screen: NSScreen?
    private var monitors: [Any] = []
    private var screenObserver: NSObjectProtocol?
    /// Set on a Mac without a notch: where the menu bar icon is, relative to the window's middle.
    private var menuBar: MenuBarAnchor?
    /// Called when the screen gains or loses a notch, e.g. when the lid closes on an external display.
    var onMenuBarModeChange: ((Bool) -> Void)?
    var menuBarMode: Bool { menuBar != nil }

    init(machine: PhaseMachine, presence: PresenceMonitor? = nil, commands: CommandRunner? = nil,
         settings: SettingsModel? = nil, anchor: @escaping () -> NSRect? = { nil }) {
        self.machine = machine
        self.presence = presence
        self.commands = commands
        self.settings = settings
        self.anchor = anchor
        panel = NotchPanel(contentRect: NSRect(origin: .zero, size: Self.canvas))
        hosting = FirstClickHostingView(rootView: IslandView(machine: machine, notch: .fallback, presence: presence, commands: commands,
                                                             settings: settings, hitArea: hitArea))
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

    func placeOnPreferredScreen() {
        guard var screen = NotchGeometry.preferredScreen() else { return }
        let wasMenuBar = menuBarMode
        var geometry = NotchGeometry(screen: screen)
        var midX = screen.frame.midX
        var menuBar: MenuBarAnchor?
        if !geometry.hasNotch || Preferences.prefersMenuBar {
            // The icon's screen holds the menu bar it's in.
            let icon = anchor()
            if let icon, let iconScreen = NSScreen.screens.first(where: { $0.frame.intersects(icon) }) {
                screen = iconScreen
                geometry = NotchGeometry(screen: screen)
            }
            // macOS can hide the icon when the menu bar is crowded: use the top-right corner then.
            let frame = screen.frame
            let iconX = icon.map(\.midX) ?? frame.maxX - 120
            // The panel stays on screen near the edges; Peeku still hangs from the icon.
            let half = MenuBarLayout.maxWidth / 2 + 8
            midX = min(max(iconX, frame.minX + half), frame.maxX - half)
            menuBar = MenuBarAnchor(offset: iconX - midX)
        }
        self.screen = screen
        notch = geometry
        self.menuBar = menuBar
        hosting.rootView = IslandView(machine: machine, notch: notch, presence: presence, commands: commands,
                                      settings: settings, menuBar: menuBar, hitArea: hitArea)
        panel.setFrame(NSRect(x: midX - Self.canvas.width / 2, y: screen.frame.maxY - Self.canvas.height,
                              width: Self.canvas.width, height: Self.canvas.height), display: true)
        if menuBarMode != wasMenuBar { onMenuBarModeChange?(menuBarMode) }
    }

    /// The menu bar icon moves when other apps add or remove theirs; follow it before showing anything.
    private func followMenuBarIcon() {
        guard let menuBar, let icon = anchor() else { return }
        let offset = icon.midX - panel.frame.midX
        if abs(offset - menuBar.offset) > 0.5 { placeOnPreferredScreen() }
    }

    /// What takes clicks, in screen coordinates: the island, or in light mode the notch, the
    /// hanging Peeku and the panel below it.
    private var islandRect: NSRect {
        guard let screen else { return .zero }
        let top = screen.frame.maxY, midX = panel.frame.midX
        let metrics = IslandMetrics.make(for: machine, notch: notch, minimal: presence?.state.minimal ?? false)
        if let menuBar {
            if metrics.glow {
                return NSRect(x: midX + menuBar.offset - metrics.width / 2, y: top - metrics.height, width: metrics.width, height: metrics.height)
            }
            // Only the panel takes clicks. Hanging Peeku overlaps the menu bar, and the icon
            // under it must stay clickable.
            guard let panel = MenuBarLayout.make(for: machine, bar: notch.barHeight).panel else { return .zero }
            let bottom = panel.top + (panel.fitsContent ? hitArea.lightPanelHeight ?? panel.height : panel.height)
            return NSRect(x: midX - panel.width / 2, y: top - bottom, width: panel.width, height: bottom - panel.top)
        }
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
            // Keys typed in Peeku's own windows (setup, the command editor) are theirs.
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
            // ⌥⌘. then ⌥⌘1–3, with ⌥⌘ still held, picks a manager tab; ⌘ alone opens a row.
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
                    self.followMenuBarIcon()
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
