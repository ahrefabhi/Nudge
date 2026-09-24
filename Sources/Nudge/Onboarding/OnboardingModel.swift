import AppKit
import Observation
import NudgeKit

/// State for the three onboarding steps. Detection runs up front, so step two is already
/// filled in, and permissions refresh every second while the window is open.
@MainActor
@Observable
final class OnboardingModel {
    enum Step: Int, CaseIterable { case hello = 1, environments, permissions }

    struct Environment: Identifiable, Equatable {
        let id: WatchedApp
        var detail: String
        var enabled: Bool
        var name: String { id.name }
    }

    enum AutomationState: Equatable {
        case granted, needsAsk, denied
        /// None of iTerm or Terminal are running; macOS asks on first use instead.
        case asksOnFirstUse
    }

    var step: Step = .hello
    var environments: [Environment] = []
    var hooks: HookInstaller.Status = .notInstalled
    /// `nil` when Codex isn't installed, so its row doesn't show.
    var codexHooks: HookInstaller.Status?
    /// Whether Nudge is Claude Code's status line, which is how it reads Claude usage.
    var claudeUsage: HookInstaller.Status = .notInstalled
    var accessibility = false
    var automation: AutomationState = .asksOnFirstUse

    @ObservationIgnored var onFinish: (() -> Void)?
    @ObservationIgnored var onEnvironmentsChanged: (() -> Void)?
    @ObservationIgnored private let sessions: () -> [NudgeSession]
    @ObservationIgnored private let otherApps: () -> [OtherApp]
    @ObservationIgnored private let hookSetup: HookSetup?
    @ObservationIgnored private var poll: Timer?
    @ObservationIgnored private var askedForAccessibility = false

    init(sessions: @escaping () -> [NudgeSession], otherApps: @escaping () -> [OtherApp] = { [] }, hookSetup: HookSetup?) {
        self.sessions = sessions
        self.otherApps = otherApps
        self.hookSetup = hookSetup
    }

    var settingsPath: String { settingsPath(.claude) }

    func settingsPath(_ target: HookInstaller.Target) -> String {
        hookSetup?.settingsPath(target) ?? (target == .claude ? "~/.claude/settings.json" : "~/.codex/hooks.json")
    }

    /// Something only System Settings can grant is still missing.
    var needsSystemSettings: Bool {
        !accessibility || automation == .needsAsk || automation == .denied
    }

    // MARK: Lifecycle

    func start() {
        refresh()
        poll = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func stop() {
        poll?.invalidate()
        poll = nil
    }

    func refresh() {
        let current = sessions()
        environments = Preferences.watchedApps(others: otherApps()).map { app in
            Environment(id: app, detail: Self.detail(for: app, sessions: current), enabled: !Preferences.isHidden(app))
        }
        if let hookSetup {
            hooks = hookSetup.status(.claude)
            codexHooks = HookSetup.availableTargets.contains(.codex) ? hookSetup.status(.codex) : nil
            claudeUsage = hookSetup.statusLineStatus()
        }
        accessibility = Permissions.accessibilityTrusted
        refreshAutomation(ask: false)
    }

    static func detail(for app: WatchedApp, sessions: [NudgeSession]) -> String {
        switch app {
        case .host(let host):
            return detail(for: host, sessions: sessions.filter { $0.host == host }.count)
        case .other(let other):
            let count = sessions.filter { $0.host == .other && ($0.hostBundleID ?? "") == other.bundleID }.count
            if count > 0 { return "\(count) session\(count == 1 ? "" : "s") found" }
            if other.isUnidentified { return "Sessions where Nudge can't tell the app" }
            return NSRunningApplication.runningApplications(withBundleIdentifier: other.bundleID).isEmpty ? "Not running" : "Running · no sessions now"
        }
    }

    static func detail(for host: HostApp, sessions count: Int) -> String {
        guard host.isInstalled else { return "Not installed" }
        let plural = count == 1 ? "" : "s"
        if count > 0 {
            return host == .vsCode ? "Claude Code extension · \(count) session\(plural)" : "\(count) session\(plural) found"
        }
        return host.isRunning ? "Running · no sessions yet" : "Not running"
    }

    // MARK: Actions

    func advance() {
        if let next = Step(rawValue: step.rawValue + 1) { step = next } else { finish() }
    }

    func finish() {
        stop()
        onFinish?()
    }

    func toggle(_ app: WatchedApp) {
        Preferences.toggle(app)
        refresh()
        onEnvironmentsChanged?()
    }

    func installHooks() { installHooks(.claude) }

    func installHooks(_ target: HookInstaller.Target) {
        hookSetup?.install(target)
        refresh()
    }

    /// Asks first, like the menu does.
    func removeHooks() { removeHooks(.claude) }

    func removeHooks(_ target: HookInstaller.Target) {
        hookSetup?.confirmAndRemove(target)
        refresh()
    }

    func setUpClaudeUsage() {
        hookSetup?.confirmAndInstallStatusLine()
        refresh()
    }

    func removeClaudeUsage() {
        hookSetup?.confirmAndRemoveStatusLine()
        refresh()
    }

    /// The first time, macOS's own prompt adds Nudge to the list; after that, open the pane.
    func allowAccessibility() {
        if askedForAccessibility { return Permissions.open(.accessibility) }
        askedForAccessibility = true
        Permissions.requestAccessibility()
    }

    /// For when Nudge shows as allowed in System Settings but isn't: that entry belongs to an
    /// older build. Clears Nudge's entries and asks again.
    func resetPermissions() {
        let alert = NSAlert()
        alert.messageText = "Reset Nudge's permissions?"
        alert.informativeText = """
        If Nudge already looks switched on in System Settings but isn't working, macOS is remembering an older \
        build of Nudge. This removes Nudge's Accessibility and Automation entries, then asks again. \
        Nothing else in your privacy settings changes.
        """
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard Permissions.resetNudgeEntries() else {
            Permissions.open(.accessibility)
            return
        }
        askedForAccessibility = false
        allowAccessibility()
        refresh()
    }

    /// Whether to offer the reset: Nudge asked, but still isn't trusted.
    var suggestsReset: Bool { askedForAccessibility && !accessibility }

    func allowAutomation() {
        if automation == .denied { return Permissions.open(.automation) }
        refreshAutomation(ask: true)
    }

    /// The footer's primary button when something is missing: the first missing permission.
    func openSystemSettings() {
        if !accessibility { return allowAccessibility() }
        allowAutomation()
    }

    // MARK: Automation

    private var automationTargets: [String] {
        let enabled = Set(environments.filter(\.enabled).compactMap(\.id.host))
        return Preferences.environments.filter { $0.needsAutomation && enabled.contains($0) && $0.isRunning }.compactMap(\.bundleID)
    }

    /// Checks (or with `ask`, requests) Automation for running iTerm and Terminal, off the main thread.
    private func refreshAutomation(ask: Bool) {
        let targets = automationTargets
        guard !targets.isEmpty else {
            automation = .asksOnFirstUse
            return
        }
        Task.detached {
            let results = targets.map { Permissions.automation(bundleID: $0, ask: ask) }
            let state: AutomationState = results.contains(.denied) ? .denied
                : results.contains(.notAsked) ? .needsAsk
                : results.allSatisfy { $0 == .notRunning } ? .asksOnFirstUse
                : .granted
            await MainActor.run { [weak self] in self?.automation = state }
        }
    }
}
