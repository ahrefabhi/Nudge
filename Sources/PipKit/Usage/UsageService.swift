import Foundation
import PipHookSchema

/// Reads Claude Code's and Codex's latest usage every so often and publishes it for the Usage tab.
/// File reads happen on a background queue; state lives on the main actor.
@MainActor
public final class UsageService {
    public var onChange: (([AgentUsage]) -> Void)?
    public private(set) var usage: [AgentUsage] = []

    private let paths: PipPaths
    private let claudeSettings: URL
    private let codexSessions: URL
    private let codexInstalled: @Sendable () -> Bool
    private let io = DispatchQueue(label: "app.pip.usage", qos: .utility)
    private var timer: Timer?

    /// Readings only change while a session runs, so there's no need to look often.
    static let interval: TimeInterval = 20

    public init(paths: PipPaths = .default, claudeSettings: URL = ClaudePaths.settings, codexSessions: URL = CodexPaths.sessions,
                codexInstalled: @escaping @Sendable () -> Bool = { CodexPaths.isInstalled }) {
        self.paths = paths
        self.claudeSettings = claudeSettings
        self.codexSessions = codexSessions
        self.codexInstalled = codexInstalled
    }

    public func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    public func refresh() {
        let (paths, settings, sessions, codexInstalled) = (paths, claudeSettings, codexSessions, codexInstalled)
        io.async { [weak self] in
            let next = Self.read(paths: paths, claudeSettings: settings, codexSessions: sessions, codexInstalled: codexInstalled())
            Task { @MainActor in self?.publish(next) }
        }
    }

    nonisolated static func read(paths: PipPaths, claudeSettings: URL, codexSessions: URL, codexInstalled: Bool) -> [AgentUsage] {
        let installer = HookInstaller(target: .claude, settingsURL: claudeSettings, paths: paths)
        let claudeConnected = installer.statusLineStatus(bundledCollector: nil) != .notInstalled
        // A reading saved before the status line was removed still says something true until it resets.
        let claudeReport = ClaudeUsageReader.read(from: paths.claudeUsage)
        let claudeSource: AgentUsage.Source = if !claudeConnected { .needsSetup }
            else if claudeReport != nil { .connected }
            else if FileManager.default.fileExists(atPath: paths.claudeStatusLineSeen.path) { .notShared }
            else { .waitingForStatusLine }
        var result = [AgentUsage(agent: .claude, source: claudeSource, report: claudeReport)]
        if codexInstalled {
            result.append(AgentUsage(agent: .codex, source: .connected, report: CodexUsageReader.read(sessions: codexSessions)))
        }
        return result
    }

    private func publish(_ next: [AgentUsage]) {
        guard next != usage else { return }
        usage = next
        onChange?(next)
    }
}
