import AppKit
import PipKit

/// Installing Pip's Claude Code hooks, always with the user's explicit go-ahead: the menu
/// confirms with an alert, onboarding with its own row explaining the change.
final class HookSetup {
    private let installer = HookInstaller()

    /// The collector shipped with this build: in the app bundle, or next to the binary in `swift run`.
    static var bundledCollector: URL? {
        let candidates = [
            Bundle.main.bundleURL.appending(path: "Contents/Helpers/pip-hook"),
            Bundle.main.executableURL?.deletingLastPathComponent().appending(path: "pip-hook"),
        ]
        return candidates.compactMap { $0 }.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    var status: HookInstaller.Status { installer.status(bundledCollector: Self.bundledCollector) }

    /// "~/.claude/settings.json", for copy.
    var settingsPath: String { tilde(installer.settingsURL) }

    func confirmAndInstall() {
        let alert = NSAlert()
        alert.messageText = status == .incomplete ? "Update Claude Code hooks?" : "Let Pip watch your Claude Code sessions?"
        alert.informativeText = """
        Pip will add \(HookInstaller.events.count) hook entries to \(tilde(installer.settingsURL)). Each one runs Pip's \
        collector, which notes what Claude is doing so Pip can show it. It never answers or approves anything.

        Your other settings and hooks stay as they are, and a backup is saved next to the file first. \
        Sessions that are already running may need a restart to report to Pip.
        """
        alert.addButton(withTitle: status == .incomplete ? "Update Hooks" : "Install Hooks")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        install()
    }

    /// Installs without asking; the caller has already explained the change. Shows any error.
    @discardableResult
    func install() -> Bool {
        do {
            guard let collector = Self.bundledCollector else { throw HookInstaller.InstallError.collectorMissing }
            try installer.install(collectorSource: collector)
            return true
        } catch {
            show(error: error)
            return false
        }
    }

    func confirmAndRemove() {
        let alert = NSAlert()
        alert.messageText = "Remove Pip's Claude Code hooks?"
        alert.informativeText = "Only Pip's entries are removed from \(tilde(installer.settingsURL)). Pip will still list running sessions, but can't say why they're waiting."
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

    private func show(error: Error) {
        let alert = NSAlert(error: error)
        NSApp.activate()
        alert.runModal()
    }

    private func tilde(_ url: URL) -> String {
        url.path.replacing(FileManager.default.homeDirectoryForCurrentUser.path, with: "~", maxReplacements: 1)
    }
}
