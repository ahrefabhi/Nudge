import Foundation

/// Sparkle installs an update where the old app was, so an app updated from Nudge or Pip first
/// launches as Nudge.app or Pip.app. This renames it to Peeku.app and relaunches, once. If the
/// rename can't happen, Peeku carries on under the old name; updates still find it.
enum BundleRename {
    static let legacyNames: Set<String> = ["Nudge", "Pip"]

    /// Returns true when a renamed copy is launching and this one should exit.
    static func run() -> Bool {
        let bundle = Bundle.main.bundleURL
        guard bundle.pathExtension == "app", legacyNames.contains(bundle.deletingPathExtension().lastPathComponent),
              // A quarantined download runs from a read-only copy; moving that would do nothing.
              !bundle.path.contains("/AppTranslocation/") else { return false }
        let renamed = bundle.deletingLastPathComponent().appending(path: "Peeku.app", directoryHint: .isDirectory)
        guard !FileManager.default.fileExists(atPath: renamed.path) else { return false }
        do {
            try FileManager.default.moveItem(at: bundle, to: renamed)
        } catch {
            NSLog("Peeku couldn't rename %@ to Peeku.app: %@", bundle.lastPathComponent, error.localizedDescription)
            return false
        }
        let open = Process()
        open.executableURL = URL(filePath: "/usr/bin/open")
        open.arguments = ["-n", renamed.path]
        do {
            try open.run()
            return true
        } catch {
            // Keep running; the app is already renamed, so the next launch is Peeku.app.
            NSLog("Peeku couldn't relaunch as Peeku.app: %@", error.localizedDescription)
            return false
        }
    }
}
