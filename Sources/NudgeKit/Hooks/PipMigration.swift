import Foundation
import NudgeHookSchema

/// Moves an install from when Nudge was called Pip over to Nudge, once: its hook handlers and
/// status line, which point at Pip's collector, then its data folder (history, saved sessions,
/// usage). Pip's folder is removed only after every handler has moved, so a failure leaves the
/// old handlers working and the next launch tries again.
public struct PipMigration: Sendable {
    public let legacy: NudgePaths
    public let current: NudgePaths
    /// Each agent's settings file; the agent's usual file when left out.
    public let settings: [HookInstaller.Target: URL]

    public init(legacy: NudgePaths = .pip, current: NudgePaths = .default, settings: [HookInstaller.Target: URL] = [:]) {
        self.legacy = legacy
        self.current = current
        self.settings = settings
    }

    public var isNeeded: Bool { FileManager.default.fileExists(atPath: legacy.root.path) }

    /// Returns the agents whose hooks were moved.
    @discardableResult
    public func run(collectorSource: URL?) throws -> [HookInstaller.Target] {
        guard isNeeded else { return [] }
        var moved: [HookInstaller.Target] = []
        for target in HookInstaller.Target.allCases {
            let old = HookInstaller(target: target, settingsURL: settings[target], paths: legacy)
            let new = HookInstaller(target: target, settingsURL: settings[target], paths: current)
            let hadHooks = old.status(bundledCollector: nil) != .notInstalled
            let hadStatusLine = old.statusLineStatus(bundledCollector: nil) != .notInstalled
            guard hadHooks || hadStatusLine else { continue }
            guard let collectorSource else { throw HookInstaller.InstallError.collectorMissing }
            if hadHooks {
                try old.uninstall()
                try new.install(collectorSource: collectorSource)
            }
            if hadStatusLine {
                // Puts back the user's own status line, which Nudge's then carries again.
                try old.uninstallStatusLine()
                try new.installStatusLine(collectorSource: collectorSource)
            }
            moved.append(target)
        }
        try moveData()
        return moved
    }

    /// Moves everything but Pip's collector into Nudge's folder, keeping anything Nudge already has.
    private func moveData() throws {
        let manager = FileManager.default
        try manager.createDirectory(at: current.root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        for item in try manager.contentsOfDirectory(at: legacy.root, includingPropertiesForKeys: nil) {
            guard item.lastPathComponent != "bin" else { continue }
            let destination = current.root.appending(path: item.lastPathComponent)
            if manager.fileExists(atPath: destination.path) {
                try mergeDirectory(item, into: destination)
            } else {
                try manager.moveItem(at: item, to: destination)
            }
        }
        try manager.removeItem(at: legacy.root)
    }

    /// Folders like the inbox may already exist on both sides; files already in Nudge's win.
    private func mergeDirectory(_ source: URL, into destination: URL) throws {
        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: source.path, isDirectory: &isDirectory), isDirectory.boolValue,
              manager.fileExists(atPath: destination.path, isDirectory: &isDirectory), isDirectory.boolValue else { return }
        for item in try manager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) {
            let target = destination.appending(path: item.lastPathComponent)
            if manager.fileExists(atPath: target.path) { try mergeDirectory(item, into: target) } else { try manager.moveItem(at: item, to: target) }
        }
    }
}
