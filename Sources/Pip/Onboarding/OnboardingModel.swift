import AppKit
import Observation
import PipKit

/// State for the three onboarding steps. Detection runs up front, so step two is already
/// filled in, and permissions refresh every second while the window is open.
@MainActor
@Observable
final class OnboardingModel {
    enum Step: Int, CaseIterable { case hello = 1, environments, permissions }

    struct Environment: Identifiable, Equatable {
        let host: HostApp
        var detail: String
        var enabled: Bool
        var id: HostApp { host }
    }

    enum AutomationState: Equatable {
        case granted, needsAsk, denied
        /// None of iTerm or Terminal are running; macOS asks on first use instead.
        case asksOnFirstUse
    }

    var step: Step = .hello
    var environments: [Environment] = []
    var hooks: HookInstaller.Status = .notInstalled
    var accessibility = false
    var automation: AutomationState = .asksOnFirstUse

    @ObservationIgnored var onFinish: (() -> Void)?
    @ObservationIgnored var onEnvironmentsChanged: (() -> Void)?
    @ObservationIgnored private let sessions: () -> [PipSession]
    @ObservationIgnored private let hookSetup: HookSetup?
    @ObservationIgnored private var poll: Timer?
    @ObservationIgnored private var askedForAccessibility = false

    init(sessions: @escaping () -> [PipSession], hookSetup: HookSetup?) {
        self.sessions = sessions
        self.hookSetup = hookSetup
    }

    var settingsPath: String { hookSetup?.settingsPath ?? "~/.claude/settings.json" }

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
        let disabled = Preferences.disabledHosts
        let current = sessions()
        environments = Preferences.environments.map { host in
            Environment(host: host, detail: Self.detail(for: host, sessions: current.filter { $0.host == host }.count),
                        enabled: !disabled.contains(host))
        }
        hooks = hookSetup?.status ?? hooks
        accessibility = Permissions.accessibilityTrusted
        refreshAutomation(ask: false)
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

    func toggle(_ host: HostApp) {
        var disabled = Preferences.disabledHosts
        if disabled.contains(host) { disabled.remove(host) } else { disabled.insert(host) }
        Preferences.disabledHosts = disabled
        refresh()
        onEnvironmentsChanged?()
    }

    func installHooks() {
        hookSetup?.install()
        refresh()
    }

    /// Asks first, like the menu does.
    func removeHooks() {
        hookSetup?.confirmAndRemove()
        refresh()
    }

    /// The first time, macOS's own prompt adds Pip to the list; after that, open the pane.
    func allowAccessibility() {
        if askedForAccessibility { return Permissions.open(.accessibility) }
        askedForAccessibility = true
        Permissions.requestAccessibility()
    }

    /// For when Pip shows as allowed in System Settings but isn't: that entry belongs to an
    /// older build. Clears Pip's entries and asks again.
    func resetPermissions() {
        let alert = NSAlert()
        alert.messageText = "Reset Pip's permissions?"
        alert.informativeText = """
        If Pip already looks switched on in System Settings but isn't working, macOS is remembering an older \
        build of Pip. This removes Pip's Accessibility and Automation entries, then asks again. \
        Nothing else in your privacy settings changes.
        """
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard Permissions.resetPipEntries() else {
            Permissions.open(.accessibility)
            return
        }
        askedForAccessibility = false
        allowAccessibility()
        refresh()
    }

    /// Whether to offer the reset: Pip asked, but still isn't trusted.
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
        let enabled = Set(environments.filter(\.enabled).map(\.host))
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
