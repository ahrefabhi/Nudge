import AppKit
import PipKit

/// Installing Pip's Claude Code and Codex hooks, always with the user's explicit go-ahead: the
/// menu confirms with an alert, onboarding with its own row explaining the change.
final class HookSetup {
    typealias Target = HookInstaller.Target

    /// The collector shipped with this build: in the app bundle, or next to the binary in `swift run`.
    static var bundledCollector: URL? {
        let candidates = [
            Bundle.main.bundleURL.appending(path: "Contents/Helpers/pip-hook"),
            Bundle.main.executableURL?.deletingLastPathComponent().appending(path: "pip-hook"),
        ]
        return candidates.compactMap { $0 }.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    /// The agents this Mac has: Claude Code always (it's Pip's first agent), Codex when installed.
    static var availableTargets: [Target] { CodexPaths.isInstalled ? [.claude, .codex] : [.claude] }

    func status(_ target: Target = .claude) -> HookInstaller.Status {
        HookInstaller(target: target).status(bundledCollector: Self.bundledCollector)
    }

    /// "~/.claude/settings.json" or "~/.codex/hooks.json", for copy.
    func settingsPath(_ target: Target = .claude) -> String { tilde(HookInstaller(target: target).settingsURL) }

    func confirmAndInstall(_ target: Target = .claude) {
        let installer = HookInstaller(target: target)
        let agent = target.agent
        let updating = status(target) == .incomplete
        let alert = NSAlert()
        alert.messageText = updating ? "Update \(agent.productName) hooks?" : "Let Pip watch your \(agent.productName) sessions?"
        var text = """
        Pip will add \(installer.events.count) hook entries to \(tilde(installer.settingsURL)). Each one runs Pip's \
        collector, which notes what \(agent.name) is doing so Pip can show it. It never answers or approves anything.

        Your other settings and hooks stay as they are, and a backup is saved next to the file first. \
        Sessions that are already running may need a restart to report to Pip.
        """
        if target == .codex { text += "\n\n" + Self.codexTrustStep }
        alert.informativeText = text
        alert.addButton(withTitle: updating ? "Update Hooks" : "Install Hooks")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        install(target)
    }

    /// Codex skips new hooks until the user trusts them; Pip can't (and shouldn't) do that for them.
    static let codexTrustStep = "Codex runs new hooks only after you trust them: in Codex, type /hooks and trust Pip's entries."

    /// Installs without asking; the caller has already explained the change. Shows any error.
    @discardableResult
    func install(_ target: Target = .claude) -> Bool {
        do {
            guard let collector = Self.bundledCollector else { throw HookInstaller.InstallError.collectorMissing }
            let added = try HookInstaller(target: target).install(collectorSource: collector)
            if target == .codex && added > 0 { showCodexTrustReminder() }
            return true
        } catch {
            show(error: error)
            return false
        }
    }

    func confirmAndRemove(_ target: Target = .claude) {
        let installer = HookInstaller(target: target)
        let alert = NSAlert()
        alert.messageText = "Remove Pip's \(target.agent.productName) hooks?"
        alert.informativeText = target == .claude
            ? "Only Pip's entries are removed from \(tilde(installer.settingsURL)). Pip will still list running sessions, but can't say why they're waiting."
            : "Only Pip's entries are removed from \(tilde(installer.settingsURL)). Pip will stop seeing Codex sessions."
        alert.addButton(withTitle: "Remove Hooks")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try installer.uninstall()
        } catch {
            show(error: error)
        }
    }

    // MARK: Claude usage

    func statusLineStatus() -> HookInstaller.Status {
        HookInstaller(target: .claude).statusLineStatus(bundledCollector: Self.bundledCollector)
    }

    /// Claude Code shares subscription usage only with its status line, so Pip becomes it.
    /// Returns true when it's set up.
    @discardableResult
    func confirmAndInstallStatusLine() -> Bool {
        let installer = HookInstaller(target: .claude)
        let hasOwn = Self.currentStatusLineCommand(in: installer.settingsURL) != nil
        let alert = NSAlert()
        alert.messageText = "Show your Claude usage in Pip?"
        alert.informativeText = """
        Claude Code shares your 5-hour and weekly limits only with its status line, so Pip will set \
        \(tilde(installer.settingsURL))'s "statusLine" to run Pip's collector, which saves those numbers for Pip to show.

        \(hasOwn ? "Your own status line keeps working: Pip runs it after saving the numbers, and puts it back if you remove this."
                 : "Pip's status line is blank. With any status line set, Claude Code hides some of its footer hints, like \"esc to interrupt\".")

        Only Claude Code in a terminal runs a status line (not the VS Code extension or the Claude app), and usage \
        is only shared on Pro and Max plans. Sessions that are already running need a restart.
        """
        alert.addButton(withTitle: "Show Usage")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        do {
            guard let collector = Self.bundledCollector else { throw HookInstaller.InstallError.collectorMissing }
            try installer.installStatusLine(collectorSource: collector)
            return true
        } catch {
            show(error: error)
            return false
        }
    }

    func confirmAndRemoveStatusLine() {
        let alert = NSAlert()
        alert.messageText = "Stop showing Claude usage?"
        alert.informativeText = "Pip will put back the status line you had before, or remove its own."
        alert.addButton(withTitle: "Stop")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try HookInstaller(target: .claude).uninstallStatusLine()
        } catch {
            show(error: error)
        }
    }

    private static func currentStatusLineCommand(in settings: URL) -> String? {
        guard let data = try? Data(contentsOf: settings), let json = try? OrderedJSON.parse(data) else { return nil }
        return json["statusLine"]?["command"]?.stringValue
    }

    private func showCodexTrustReminder() {
        let alert = NSAlert()
        alert.messageText = "One more step in Codex"
        alert.informativeText = Self.codexTrustStep + " Until then Codex skips them, and Pip won't see Codex sessions."
        alert.addButton(withTitle: "OK")
        NSApp.activate()
        alert.runModal()
    }

    private func show(error: Error) {
        let alert = NSAlert(error: error)
        NSApp.activate()
        alert.runModal()
    }

    private func tilde(_ url: URL) -> String {
        url.path.replacing(FileManager.default.homeDirectoryForCurrentUser.path, with: "~", maxReplacements: 1)
    }
}
