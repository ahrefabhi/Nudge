import AppKit
import Carbon.HIToolbox
import PeekuKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let machine = PhaseMachine()
    private let observation = ObservationService()
    private let usage = UsageService()
    private let spend = SpendService()
    private var usageAlerts = UsageAlerts(handled: Preferences.handledUsageAlerts)
    private let hookSetup = HookSetup()
    private lazy var demo = DemoController(machine: machine)
    private var demoMode = CommandLine.arguments.contains("--demo")
    /// Before setup is done, the setup window is all Peeku shows: no notch, hotkeys or chimes.
    private var setupPending = false
    private var notch: NotchWindowController?
    private var statusMenu: StatusMenu?
    private var hotKeys: HotKeys?
    private var characterSheet: NSWindow?
    private var onboarding: OnboardingWindow?
    private var settings: SettingsWindow?
    private let focusRing = FocusRing()
    private let presence = PresenceMonitor()
    private let updater = Updater()
    private let historyStore = HistoryStore()
    private lazy var history = HistoryRecorder(entries: historyStore.load())
    private let commands = CommandRunner()
    private lazy var commandWindows = CommandWindows(runner: commands)

    func applicationDidFinishLaunching(_ notification: Notification) {
        LegacyUpgrade.run()
        commands.stopLeftovers()
        commands.onEdit = { [weak self] command in self?.openCommandWindow { $0.edit(command) } }
        commands.onShowLog = { [weak self] command in self?.openCommandWindow { $0.showLog(command) } }
        commands.onChange = { [weak self] in self?.deliverCommandAlerts() }
        let notch = NotchWindowController(machine: machine, presence: presence, commands: commands)
        machine.onOpen = { [weak self] session in
            switch session.kind {
            case .usage: self?.openedUsageAlert(session)
            case .command, .commandInput: self?.openedCommandAlert(session)
            default: self?.focus(session)
            }
        }
        machine.onRestartCommand = { [weak self] alert in
            guard let self else { return }
            if self.demoMode { return self.demo.didOpen(alert) }
            if let id = CommandRunner.commandID(forAlert: alert) { self.commands.restart(id) }
        }
        machine.onAnswerCommand = { [weak self] alert, answer in
            guard let self else { return }
            if self.demoMode { return self.demo.didOpen(alert) }
            if let id = CommandRunner.commandID(forAlert: alert) { self.commands.send(id, answer + "\r") }
        }
        machine.onChime = { Sounds.play($0) }
        machine.isInView = { [weak self] session in
            guard let self, !self.demoMode, Preferences.quietInView, session.kind != .usage, !session.kind.isCommand else { return false }
            return ForegroundSession.isInView(session, observed: self.observation.observed(session.id))
        }
        applyPreferences()
        presence.onChange = { [weak self] state in self?.machine.muted = state.muted }
        presence.start()

        observation.onChange = { [weak self] _ in self?.deliverSessions() }
        observation.start()
        machine.setUsageAlertRules(Preferences.usageAlertRules)
        machine.onUsageAlertRulesChanged = { [weak self] rules in
            Preferences.usageAlertRules = rules
            self?.deliverUsageAlerts()
        }
        usage.onChange = { [weak self] in
            self?.machine.usage = $0
            self?.deliverUsageAlerts()
        }
        spend.onChange = { [weak self] in self?.machine.spend = $0 }
        machine.onShowUsageTab = { [weak self] in
            self?.usage.refreshNow()
            self?.spend.refresh()
        }
        usage.start()
        spend.start()
        machine.onSetUpUsage = { [weak self] agent in
            guard agent == .claude else { return }
            // The notch panel floats above ordinary windows, so close the manager before the alert shows.
            self?.machine.tapOutside()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                guard let self, self.hookSetup.confirmAndInstallStatusLine() else { return }
                self.usage.refresh()
            }
        }
        if demoMode { demo.reset() }

        statusMenu = StatusMenu(actions: .init(
            sessionCount: { [weak self] in self?.visibleSessions.count ?? 0 },
            hookTargets: { HookSetup.availableTargets },
            hookStatus: { [weak self] in self?.hookSetup.status($0) ?? .notInstalled },
            installHooks: { [weak self] in self?.hookSetup.confirmAndInstall($0) },
            removeHooks: { [weak self] in self?.hookSetup.confirmAndRemove($0) },
            isDemo: { [weak self] in self?.demoMode ?? false },
            setDemo: { [weak self] in self?.setDemoMode($0) },
            simulate: { [weak self] in self?.demo.trigger($0) },
            simulateUsage: { [weak self] in self?.demo.triggerUsage() },
            simulateCommandFailure: { [weak self] in self?.demo.triggerCommandFailure() },
            simulateCommandPrompt: { [weak self] in self?.demo.triggerCommandPrompt() },
            resetDemo: { [weak self] in self?.demo.reset() },
            toggleManager: { [weak self] in self?.toggleManager() },
            showCharacterSheet: { [weak self] in self?.showCharacterSheet() },
            showSetup: { [weak self] in self?.showOnboarding() },
            showSettings: { [weak self] in self?.showSettings() },
            canCheckForUpdates: { [weak self] in self?.updater.canCheck ?? false },
            checkForUpdates: { [weak self] in self?.updater.checkForUpdates() },
            quietUntil: { Preferences.quietUntil.flatMap { $0 > Date() ? $0 : nil } },
            setQuiet: { [weak self] until in
                Preferences.quietUntil = until
                self?.presence.refresh()
            },
            otherApps: { [weak self] in self?.otherApps ?? [] },
            toggleApp: { [weak self] app in self?.toggle(app) }
        ))

        self.notch = notch
        // Sessions are still read during setup, so it can say which apps have some running.
        setupPending = !Preferences.onboardingCompleted && !demoMode
        if setupPending { showOnboarding() } else { startNotch() }
    }

    /// The notch and its hotkeys, once setup is out of the way.
    private func startNotch() {
        let hotKeys = HotKeys()
        // ⌥⌘. rather than ⌘⇧., which Finder and Open/Save dialogs use to show hidden files.
        hotKeys.register(keyCode: kVK_ANSI_Period, modifiers: cmdKey | optionKey) { [weak self] in self?.toggleManager() }
        hotKeys.register(keyCode: kVK_DownArrow, modifiers: cmdKey | optionKey) { [weak self] in
            self?.machine.cycleNext()
            self?.notch?.focusIsland()
        }
        self.hotKeys = hotKeys
        notch?.show()
        deliverSessions()
        deliverUsageAlerts()
        deliverCommandAlerts()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Quick commands belong to Peeku's run; a dev server left behind would keep its port.
        commands.stopAll()
        observation.stop()
        usage.stop()
        spend.stop()
    }

    // MARK: Sessions

    /// Real sessions, minus apps the user turned off.
    private var visibleSessions: [PeekuSession] {
        let filter = Preferences.hostFilter
        return observation.sessions.filter { !filter.hides($0) }
    }

    private func deliverSessions() {
        // History sees every session, so hiding an app never reads as its sessions being answered.
        // It keeps recording in Demo Mode; it just isn't shown.
        if history.record(observation.sessions) { historyStore.save(history.entries) }
        guard !demoMode, !setupPending else { return }
        let filter = Preferences.hostFilter
        machine.update(sessions: visibleSessions)
        machine.history = history.entries.filter { !filter.hides($0) }
    }

    /// Rate limits past the user's threshold join the queue after sessions that need you.
    private func deliverUsageAlerts() {
        guard !demoMode, !setupPending else { return }
        let alerts = usageAlerts.update(usage.usage, rules: machine.usageAlertRules)
        if usageAlerts.handled != Preferences.handledUsageAlerts { Preferences.handledUsageAlerts = usageAlerts.handled }
        machine.update(usageAlerts: alerts)
    }

    /// Quick commands that exited with an error queue like sessions that need you.
    private func deliverCommandAlerts() {
        guard !demoMode, !setupPending else { return }
        machine.update(commandAlerts: commands.alerts)
    }

    /// The notch has folded; show the failed command's output.
    private func openedCommandAlert(_ alert: PeekuSession) {
        if demoMode { return demo.didOpen(alert) }
        guard let id = CommandRunner.commandID(forAlert: alert), let command = commands.command(id) else { return }
        openCommandWindow { $0.showLog(command) }
    }

    /// The machine has already switched the manager to its Usage tab.
    private func openedUsageAlert(_ alert: PeekuSession) {
        if demoMode { return demo.didOpen(alert) }
        usageAlerts.handle(alert.id)
        deliverUsageAlerts()
    }

    /// Apps besides the built-in four that sessions have run in, for the menu and Settings.
    private var otherApps: [OtherApp] {
        OtherApp.seen(sessions: observation.sessions, history: history.entries, hidden: Preferences.disabledApps) { bundleID in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map { FileManager.default.displayName(atPath: $0.path) }
        }
    }

    private func toggle(_ app: WatchedApp) {
        Preferences.toggle(app)
        deliverSessions()
    }

    // MARK: Actions

    private func focus(_ session: PeekuSession) {
        if demoMode { return demo.didOpen(session) }
        let observed = observation.observed(session.id)
        switch SessionOpener.open(session, observed: observed) {
        case .success:
            // The hook's bundle id is the exact app (e.g. VS Code Insiders, Warp); the host type is the fallback.
            if let bundleID = observed?.host.resolvedBundleID ?? session.host.bundleID {
                focusRing.flash(appBundleID: bundleID, color: session.kind.accent)
            }
        case .failure(let failure):
            NSLog("Peeku couldn't open %@: %@", session.project, failure.description)
            if case .automationDenied = failure { showAutomationHelp(failure) } else { NSSound.beep() }
        }
    }

    private func setDemoMode(_ on: Bool) {
        demoMode = on
        if on {
            demo.reset()
        } else {
            deliverSessions()
            deliverUsageAlerts()
            deliverCommandAlerts()
        }
    }

    private func toggleManager() {
        if setupPending { return showOnboarding() }
        machine.toggleManager()
        if machine.phase == .manager { notch?.focusIsland() }
    }

    private func applyPreferences() {
        machine.autoCollapse = Preferences.autoCollapse
        machine.expandFinished = Preferences.popUpOnFinish
    }

    private func showSettings() {
        if let settings { return settings.show() }
        let setup = OnboardingModel(sessions: { [weak self] in self?.observation.sessions ?? [] },
                                    otherApps: { [weak self] in self?.otherApps ?? [] }, hookSetup: hookSetup)
        setup.onEnvironmentsChanged = { [weak self] in self?.deliverSessions() }
        let model = SettingsModel(setup: setup, updater: updater)
        model.onPreferencesChanged = { [weak self] in self?.applyPreferences() }
        model.onQuietChanged = { [weak self] in self?.presence.refresh() }
        model.onEditUsageAlerts = { [weak self] in
            self?.machine.showUsage()
            self?.notch?.focusIsland()
        }
        let window = SettingsWindow(model: model)
        settings = window
        window.show()
    }

    /// The notch panel floats above ordinary windows, so close the manager before the window shows.
    private func openCommandWindow(_ open: @escaping (CommandWindows) -> Void) {
        machine.tapOutside()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self else { return }
            open(self.commandWindows)
        }
    }

    private func showOnboarding() {
        if let onboarding { return onboarding.show() }
        let model = OnboardingModel(sessions: { [weak self] in self?.observation.sessions ?? [] },
                                    otherApps: { [weak self] in self?.otherApps ?? [] }, hookSetup: hookSetup)
        model.onEnvironmentsChanged = { [weak self] in self?.deliverSessions() }
        let window = OnboardingWindow(model: model) { [weak self] in
            Preferences.onboardingCompleted = true
            self?.onboarding = nil
            if self?.setupPending == true {
                self?.setupPending = false
                self?.startNotch()
            }
        }
        onboarding = window
        window.show()
    }

    private func showCharacterSheet() {
        let window = characterSheet ?? CharacterSheet.makeWindow()
        characterSheet = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func showAutomationHelp(_ failure: SessionOpener.Failure) {
        let alert = NSAlert()
        alert.messageText = "Peeku needs permission to switch tabs"
        alert.informativeText = failure.description
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Not Now")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn { Permissions.open(.automation) }
    }
}
