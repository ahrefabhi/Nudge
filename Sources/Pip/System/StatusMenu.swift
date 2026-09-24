import AppKit
import PipKit

/// Menu bar item: hook setup, demo mode and quit. Rebuilt each time it opens, so it's always current.
final class StatusMenu: NSObject, NSMenuDelegate {
    struct Actions {
        var sessionCount: () -> Int
        var hookStatus: () -> HookInstaller.Status
        var installHooks: () -> Void
        var removeHooks: () -> Void
        var isDemo: () -> Bool
        var setDemo: (Bool) -> Void
        var simulate: (MockSessions.Event) -> Void
        var resetDemo: () -> Void
        var toggleManager: () -> Void
        var showCharacterSheet: () -> Void
        var showSetup: () -> Void
        var showSettings: () -> Void
        var canCheckForUpdates: () -> Bool
        var checkForUpdates: () -> Void
        var quietUntil: () -> Date?
        var setQuiet: (Date?) -> Void
        var toggleEnvironment: (HostApp) -> Void
    }

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let actions: Actions

    init(actions: Actions) {
        self.actions = actions
        super.init()
        item.button?.image = NSImage(systemSymbolName: "eyes", accessibilityDescription: "Pip")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        handlers.removeAll()
        let demo = actions.isDemo()

        let count = actions.sessionCount()
        menu.addItem(disabled(demo ? "Showing demo sessions" : count == 0 ? "No Claude Code sessions" : "Watching \(count) session\(count == 1 ? "" : "s")"))

        switch actions.hookStatus() {
        case .installed:
            menu.addItem(disabled("Claude Code hooks installed"))
            menu.addItem(entry("Remove Claude Code Hooks…") { $0.actions.removeHooks() })
        case .incomplete:
            menu.addItem(disabled("Claude Code hooks need an update"))
            menu.addItem(entry("Update Claude Code Hooks…") { $0.actions.installHooks() })
            menu.addItem(entry("Remove Claude Code Hooks…") { $0.actions.removeHooks() })
        case .notInstalled:
            menu.addItem(disabled("Pip can't see why sessions wait yet"))
            menu.addItem(entry("Install Claude Code Hooks…") { $0.actions.installHooks() })
        }

        menu.addItem(.separator())
        let manager = entry("Session Manager") { $0.actions.toggleManager() }
        // Shown for reference; the global hotkey does the work outside this menu.
        manager.keyEquivalent = "."
        manager.keyEquivalentModifierMask = [.option, .command]
        menu.addItem(manager)

        let environments = NSMenu()
        let hiddenHosts = Preferences.disabledHosts
        for host in Preferences.environments {
            let item = entry(host.onboardingName) { $0.actions.toggleEnvironment(host) }
            item.state = hiddenHosts.contains(host) ? .off : .on
            environments.addItem(item)
        }
        let environmentsItem = NSMenuItem(title: "Watch Sessions In", action: nil, keyEquivalent: "")
        environmentsItem.submenu = environments
        menu.addItem(environmentsItem)
        menu.addItem(entry("Set Up Pip…") { $0.actions.showSetup() })
        let settings = entry("Settings…") { $0.actions.showSettings() }
        settings.keyEquivalent = ","
        settings.keyEquivalentModifierMask = [.command]
        menu.addItem(settings)
        let updates = entry("Check for Updates…") { $0.actions.checkForUpdates() }
        updates.isEnabled = actions.canCheckForUpdates()
        menu.addItem(updates)

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
            simulate.addItem(.separator())
            simulate.addItem(entry("Reset") { $0.actions.resetDemo() })
            let simulateItem = NSMenuItem(title: "Simulate", action: nil, keyEquivalent: "")
            simulateItem.submenu = simulate
            menu.addItem(simulateItem)
        }
        menu.addItem(entry("Character Sheet") { $0.actions.showCharacterSheet() })

        menu.addItem(.separator())
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
            let quietItem = NSMenuItem(title: "Quiet", action: nil, keyEquivalent: "")
            quietItem.submenu = quiet
            menu.addItem(quietItem)
        }

        menu.addItem(.separator())
        menu.addItem(entry("Uninstall Pip…") { _ in Uninstaller.confirmAndUninstall() })
        menu.addItem(NSMenuItem(title: "Quit Pip", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
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

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @objc private func performEntry(_ sender: NSMenuItem) {
        handlers[sender.tag]?(self)
    }
}
