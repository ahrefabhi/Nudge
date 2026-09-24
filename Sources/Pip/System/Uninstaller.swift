import AppKit
import PipHookSchema
import PipKit

/// Removes everything Pip added to the Mac, after the user confirms: its Claude Code hooks,
/// its data folder (collector, inbox, history, saved sessions), its login item, settings and
/// caches, and finally the app itself, which goes to the Trash.
enum Uninstaller {
    static func confirmAndUninstall() {
        let installer = HookInstaller()
        let settings = installer.settingsURL.path.replacing(FileManager.default.homeDirectoryForCurrentUser.path, with: "~", maxReplacements: 1)
        let alert = NSAlert()
        alert.messageText = "Uninstall Pip?"
        alert.informativeText = """
        Pip will remove its hooks from \(settings) (your other settings and hooks stay), delete its history and \
        saved data, stop opening at login, and move itself to the Trash.

        Backups Pip made of your Claude settings (settings.json.pip-backup-…) are left where they are.
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Uninstall")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        // Hooks first: if they can't be removed, stop before deleting the collector they point at.
        do {
            try installer.uninstall()
        } catch {
            NSApp.activate()
            NSAlert(error: error).runModal()
            return
        }
        try? LoginItem.set(false)

        let manager = FileManager.default
        try? manager.removeItem(at: PipPaths.default.root)
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
