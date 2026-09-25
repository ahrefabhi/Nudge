import Foundation
import PeekuHookSchema
import PeekuKit

/// Carries an install over from Nudge or Pip, Peeku's old names, on the first launch after the
/// rename: settings, hooks, status line and data. Accessibility and Automation can't move with
/// them, since macOS ties those to the bundle ID, so the old app's stale entries are cleared instead.
enum LegacyUpgrade {
    /// Newest first, so a Nudge install wins over anything Pip left behind.
    static let legacy: [(name: String, bundleID: String, paths: PeekuPaths)] = [
        ("Nudge", "app.nudge.Nudge", .nudge),
        ("Pip", "app.pip.Pip", .pip),
    ]

    static func run() {
        // A custom data folder is a development setup; leave the real old install alone.
        guard ProcessInfo.processInfo.environment["PEEKU_HOME"] == nil else { return }
        for app in legacy {
            moveDefaults(from: app.bundleID)
            let migration = LegacyMigration(legacy: app.paths)
            guard migration.isNeeded else { continue }
            do {
                try migration.run(collectorSource: HookSetup.bundledCollector)
                Permissions.resetEntries(for: app.bundleID)
            } catch {
                // The old handlers keep working until this succeeds; the next launch tries again.
                NSLog("Peeku couldn't move %@'s hooks and data: %@", app.name, error.localizedDescription)
            }
        }
    }

    private static func moveDefaults(from bundleID: String) {
        let defaults = UserDefaults.standard
        guard Bundle.main.bundleIdentifier != bundleID, let old = defaults.persistentDomain(forName: bundleID) else { return }
        for (key, value) in old where defaults.object(forKey: key) == nil { defaults.set(value, forKey: key) }
        defaults.removePersistentDomain(forName: bundleID)
    }
}
