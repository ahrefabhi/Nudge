import AppKit
import PeekuKit

/// Menu bar item: hook setup, demo mode and quit. Rebuilt each time it opens, so it's always current.
/// On a Mac without a notch it's also where Peeku lives: its eyes show the state, a click opens
/// the session manager and a right-click (or ⌃-click) opens this menu.
final class StatusMenu: NSObject, NSMenuDelegate {
    struct Actions {
        var sessionCount: () -> Int
        var hookTargets: () -> [HookInstaller.Target]
        var hookStatus: (HookInstaller.Target) -> HookInstaller.Status
        var installHooks: (HookInstaller.Target) -> Void
        var removeHooks: (HookInstaller.Target) -> Void
        var isDemo: () -> Bool
        var setDemo: (Bool) -> Void
        var simulate: (MockSessions.Event) -> Void
        var simulateUsage: () -> Void
        var simulateCommandFailure: () -> Void
        var simulateCommandPrompt: () -> Void
        var resetDemo: () -> Void
        var toggleManager: () -> Void
        var showCharacterSheet: () -> Void
        var showSetup: () -> Void
        var showSettings: () -> Void
        var canCheckForUpdates: () -> Bool
        var checkForUpdates: () -> Void
        var quietUntil: () -> Date?
        var setQuiet: (Date?) -> Void
        /// Other apps sessions have run in, e.g. Warp.
        var otherApps: () -> [OtherApp]
        var toggleApp: (WatchedApp) -> Void
    }

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let actions: Actions
    private let menu = NSMenu()
    private var glanceTimer: Timer?
    private var glance = 0
    private var appearanceObservation: NSKeyValueObservation?

    /// A click on the icon in menu bar mode.
    var onClick: (() -> Void)?

    /// No notch: the icon shows Peeku's state and a click opens the manager instead of the menu.
    var menuBarMode = false {
        didSet {
            guard menuBarMode != oldValue else { return }
            item.menu = menuBarMode ? nil : menu
            refreshIcon()
        }
    }

    /// What Peeku is doing, for the icon's eyes in menu bar mode.
    var iconState = MenuBarIcon.State() {
        didSet { if iconState != oldValue { refreshIcon() } }
    }

    /// Lit while the manager or an alert hangs from the icon, like an open menu.
    var highlighted = false {
        didSet { item.button?.highlight(highlighted && menuBarMode) }
    }

    /// The icon's frame on screen, which the notch panel hangs from in menu bar mode.
    var anchor: NSRect? {
        guard let button = item.button, let window = button.window, window.isVisible else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    init(actions: Actions) {
        self.actions = actions
        super.init()
        menu.delegate = self
        item.menu = menu
        if let button = item.button {
            button.target = self
            button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            appearanceObservation = button.observe(\.effectiveAppearance) { [weak self] _, _ in
                DispatchQueue.main.async { self?.refreshIcon() }
            }
        }
        refreshIcon()
    }

    @objc private func clicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            // Shows the menu once, then the icon goes back to opening the manager.
            item.menu = menu
            item.button?.performClick(nil)
            item.menu = menuBarMode ? nil : menu
        } else {
            onClick?()
        }
    }

    private func refreshIcon() {
        guard let button = item.button else { return }
        let dark = button.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        var state = iconState
        state.glance = [0, -1, 0, 1][glance % 4]
        button.image = MenuBarIcon.image(menuBarMode ? state : nil, darkMenuBar: dark)
        // Working eyes glance around, like Peeku in the notch.
        let glancing = menuBarMode && iconState.mood == .working && iconState.count == 0
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if glancing, glanceTimer == nil {
            glanceTimer = Timer.scheduledTimer(withTimeInterval: 0.9, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.glance += 1
                    self.refreshIcon()
                }
            }
        } else if !glancing, let timer = glanceTimer {
            timer.invalidate()
            glanceTimer = nil
            glance = 0
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        handlers.removeAll()
        let demo = actions.isDemo()

        let count = actions.sessionCount()
        menu.addItem(disabled(demo ? "Showing demo sessions" : count == 0 ? "No agent sessions" : "Watching \(count) session\(count == 1 ? "" : "s")"))

        // What Peeku is watching, and how loudly.
        let manager = entry("Session Manager") { $0.actions.toggleManager() }
        // Shown for reference; the global hotkey does the work outside this menu.
        manager.keyEquivalent = "."
        manager.keyEquivalentModifierMask = [.option, .command]
        menu.addItem(manager)
        addQuiet(to: menu)

        let environments = NSMenu()
        for app in Preferences.watchedApps(others: actions.otherApps()) {
            // The built-in apps, then a line, then the others.
            if case .other = app, environments.items.count == Preferences.environments.count { environments.addItem(.separator()) }
            let item = entry(app.name) { $0.actions.toggleApp(app) }
            item.state = Preferences.isHidden(app) ? .off : .on
            environments.addItem(item)
        }
        menu.addItem(submenu("Watch Sessions In", environments))

        // Hooks.
        menu.addItem(.separator())
        for target in actions.hookTargets() {
            let name = target.agent.productName
            switch actions.hookStatus(target) {
            case .installed:
                menu.addItem(disabled("\(name) hooks installed"))
                menu.addItem(entry("Remove \(name) Hooks…") { $0.actions.removeHooks(target) })
            case .incomplete:
                menu.addItem(disabled("\(name) hooks need an update"))
                menu.addItem(entry("Update \(name) Hooks…") { $0.actions.installHooks(target) })
                menu.addItem(entry("Remove \(name) Hooks…") { $0.actions.removeHooks(target) })
            case .notInstalled:
                menu.addItem(disabled(target == .claude ? "Peeku can't see why sessions wait yet" : "Peeku can't see Codex sessions yet"))
                menu.addItem(entry("Install \(name) Hooks…") { $0.actions.installHooks(target) })
            }
        }

        // Trying Peeku out.
        menu.addItem(.separator())
        let demoItem = entry("Demo Mode") { $0.actions.setDemo(!demo) }
        demoItem.state = demo ? .on : .off
        menu.addItem(demoItem)
        if demo {
            let simulate = NSMenu()
            let events: [(String, MockSessions.Event)] = [
                ("Permission Request", .permission), ("Question", .question), ("Error", .error),
                ("Finished", .success), ("3 Agents Waiting", .multiple),
            ]
            for (title, event) in events { simulate.addItem(entry(title) { $0.actions.simulate(event) }) }
            simulate.addItem(entry("Usage Limit") { $0.actions.simulateUsage() })
            simulate.addItem(entry("Command Failure") { $0.actions.simulateCommandFailure() })
            simulate.addItem(entry("Command Waiting for Input") { $0.actions.simulateCommandPrompt() })
            simulate.addItem(.separator())
            simulate.addItem(entry("Reset") { $0.actions.resetDemo() })
            menu.addItem(submenu("Simulate", simulate))
        }
        menu.addItem(entry("Character Sheet") { $0.actions.showCharacterSheet() })

        // The app itself. macOS indents a whole section when one item has an icon, so all of these get one.
        menu.addItem(.separator())
        menu.addItem(symbol(entry("Set Up Peeku…") { $0.actions.showSetup() }, "wand.and.stars"))
        let updates = symbol(entry("Check for Updates…") { $0.actions.checkForUpdates() }, "arrow.triangle.2.circlepath")
        updates.isEnabled = actions.canCheckForUpdates()
        menu.addItem(updates)
        let settings = symbol(entry("Settings…") { $0.actions.showSettings() }, "gearshape")
        settings.keyEquivalent = ","
        settings.keyEquivalentModifierMask = [.command]
        menu.addItem(settings)

        menu.addItem(.separator())
        menu.addItem(symbol(entry("Uninstall Peeku…") { _ in Uninstaller.confirmAndUninstall() }, "trash"))
        menu.addItem(symbol(NSMenuItem(title: "Quit Peeku", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"), "power"))
    }

    private func addQuiet(to menu: NSMenu) {
        if let until = actions.quietUntil() {
            menu.addItem(disabled("Quiet until \(until.formatted(date: Calendar.current.isDateInToday(until) ? .omitted : .abbreviated, time: .shortened))"))
            menu.addItem(entry("Resume Notifications") { $0.actions.setQuiet(nil) })
        } else {
            let quiet = NSMenu()
            quiet.addItem(entry("For 1 Hour") { $0.actions.setQuiet(Date().addingTimeInterval(3600)) })
            quiet.addItem(entry("Until Tomorrow") {
                let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date()))
                $0.actions.setQuiet(tomorrow.flatMap { Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: $0) })
            })
            menu.addItem(submenu("Quiet", quiet))
        }
    }

    // MARK: Items

    private var handlers: [Int: (StatusMenu) -> Void] = [:]

    private func entry(_ title: String, _ handler: @escaping (StatusMenu) -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(performEntry(_:)), keyEquivalent: "")
        item.target = self
        item.tag = handlers.count + 1
        handlers[item.tag] = handler
        return item
    }

    private func submenu(_ title: String, _ submenu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    private func symbol(_ item: NSMenuItem, _ name: String) -> NSMenuItem {
        item.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        return item
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @objc private func performEntry(_ sender: NSMenuItem) {
        handlers[sender.tag]?(self)
    }
}
