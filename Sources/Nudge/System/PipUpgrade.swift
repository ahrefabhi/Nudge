import Foundation
import NudgeKit

/// Carries an install over from Pip, Nudge's old name, on the first launch after the rename:
/// settings, hooks, status line and data. Accessibility and Automation can't move with them,
/// since macOS ties those to the bundle ID, so Pip's stale entries are cleared instead.
enum PipUpgrade {
    static let bundleID = "app.pip.Pip"

    static func run() {
        // A custom data folder is a development setup; leave the real Pip install alone.
        guard ProcessInfo.processInfo.environment["NUDGE_HOME"] == nil else { return }
        moveDefaults()
        let migration = PipMigration()
        guard migration.isNeeded else { return }
        do {
            try migration.run(collectorSource: HookSetup.bundledCollector)
            Permissions.resetEntries(for: bundleID)
        } catch {
            // Pip's handlers keep working until this succeeds; the next launch tries again.
            NSLog("Nudge couldn't move Pip's hooks and data: %@", error.localizedDescription)
        }
    }

    private static func moveDefaults() {
        let defaults = UserDefaults.standard
        guard Bundle.main.bundleIdentifier != bundleID, let old = defaults.persistentDomain(forName: bundleID) else { return }
        for (key, value) in old where defaults.object(forKey: key) == nil { defaults.set(value, forKey: key) }
        defaults.removePersistentDomain(forName: bundleID)
    }
}
