import AppKit
import NudgeHookSchema
import NudgeKit

/// Removes everything Nudge added to the Mac, after the user confirms: its Claude Code and Codex hooks,
/// its data folder (collector, inbox, history, saved sessions), its login item, settings and
/// caches, and finally the app itself, which goes to the Trash.
enum Uninstaller {
    static func confirmAndUninstall() {
        let installers = HookSetup.availableTargets.map { HookInstaller(target: $0) }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let files = installers.map { $0.settingsURL.path.replacing(home, with: "~", maxReplacements: 1) }.joined(separator: " and ")
        let alert = NSAlert()
        alert.messageText = "Uninstall Nudge?"
        alert.informativeText = """
        Nudge will remove its hooks and status line from \(files) (your other settings and hooks stay), delete its history and \
        saved data, stop opening at login, and move itself to the Trash.

        Backups Nudge made of those files (….nudge-backup-…) are left where they are.
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Uninstall")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        // Hooks first: if they can't be removed, stop before deleting the collector they point at.
        do {
            for installer in installers { try installer.uninstall() }
            // Puts back the user's own status line, if Nudge had taken its place.
            try HookInstaller(target: .claude).uninstallStatusLine()
        } catch {
            NSApp.activate()
            NSAlert(error: error).runModal()
            return
        }
        try? LoginItem.set(false)

        let manager = FileManager.default
        try? manager.removeItem(at: NudgePaths.default.root)
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
            if let caches = manager.urls(for: .cachesDirectory, in: .userDomainMask).first {
                try? manager.removeItem(at: caches.appending(path: bundleID))
            }
        }

        // `swift run` has no bundle to throw away.
        guard Bundle.main.bundleURL.pathExtension == "app" else { return NSApp.terminate(nil) }
        NSWorkspace.shared.recycle([Bundle.main.bundleURL]) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
