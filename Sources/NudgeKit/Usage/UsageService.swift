import Foundation
import NudgeHookSchema

/// Reads Claude Code's and Codex's latest usage every so often and publishes it for the Usage tab.
/// File reads happen on a background queue, asking the agents' own tools on another (they can be
/// slow); state lives on the main actor.
@MainActor
public final class UsageService {
    public var onChange: (([AgentUsage]) -> Void)?
    public private(set) var usage: [AgentUsage] = []

    private let paths: NudgePaths
    private let claudeSettings: URL
    private let codexSessions: URL
    private let codexInstalled: @Sendable () -> Bool
    private let io = DispatchQueue(label: "app.nudge.usage", qos: .utility)
    private let live = DispatchQueue(label: "app.nudge.usage.live", qos: .utility)
    private var timer: Timer?
    private let askAgents: Bool
    /// When Nudge last asked the agents, and Codex's own answer.
    private var askedAt: Date?
    private var codexLive: UsageReport?
    /// Claude Code's own answer.
    private var claudeLive: ClaudeLiveUsage.Answer?
    private var asking = false

    /// Session logs and the status line's file are cheap to read.
    static let interval: TimeInterval = 20
    /// Asking an agent is a network request on its side, so not too often.
    static let liveInterval: TimeInterval = 5 * 60
    /// Opening the Usage tab asks again, unless Nudge just did.
    static let onDemandInterval: TimeInterval = 60

    public init(paths: NudgePaths = .default, claudeSettings: URL = ClaudePaths.settings, codexSessions: URL = CodexPaths.sessions,
                codexInstalled: @escaping @Sendable () -> Bool = { CodexPaths.isInstalled }, askAgents: Bool = true) {
        self.paths = paths
        self.claudeSettings = claudeSettings
        self.codexSessions = codexSessions
        self.codexInstalled = codexInstalled
        self.askAgents = askAgents
    }

    public func start() {
        refresh()
        askAgentsIfDue()
        timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
                self?.askAgentsIfDue()
            }
        }
    }

    /// For when the user looks at the Usage tab: fresh numbers unless they're under a minute old.
    public func refreshNow() {
        refresh()
        askAgentsIfDue(after: Self.onDemandInterval)
    }

    /// Asks Claude Code and Codex for their live limits, when due. A failed answer keeps the last good one.
    private func askAgentsIfDue(after interval: TimeInterval = UsageService.liveInterval) {
        guard askAgents, !asking else { return }
        let now = Date()
        guard askedAt.map({ now.timeIntervalSince($0) >= interval }) ?? true else { return }
        asking = true
        askedAt = now
        let askCodex = codexInstalled()
        live.async { [weak self] in
            let claude = ClaudeLiveUsage.read()
            let codex = askCodex ? CodexLiveUsage.read() : nil
            Task { @MainActor in
                guard let self else { return }
                self.asking = false
                if let claude { self.claudeLive = claude }
                if let codex { self.codexLive = codex }
                self.refresh()
            }
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    public func refresh() {
        let (paths, settings, sessions, codexInstalled) = (paths, claudeSettings, codexSessions, codexInstalled)
        let (codexLive, claudeLive) = (codexLive, claudeLive)
        io.async { [weak self] in
            let next = Self.read(paths: paths, claudeSettings: settings, codexSessions: sessions, codexInstalled: codexInstalled(),
                                 codexLive: codexLive, claudeLive: claudeLive)
            Task { @MainActor in self?.publish(next) }
        }
    }

    /// `claudeLive` and `codexLive` are the agents' own latest answers; the newer of each and
    /// what the status line or session logs recorded wins.
    nonisolated static func read(paths: NudgePaths, claudeSettings: URL, codexSessions: URL, codexInstalled: Bool,
                                 codexLive: UsageReport? = nil, claudeLive: ClaudeLiveUsage.Answer? = nil) -> [AgentUsage] {
        let installer = HookInstaller(target: .claude, settingsURL: claudeSettings, paths: paths)
        let claudeConnected = installer.statusLineStatus(bundledCollector: nil) != .notInstalled
        // A reading saved before the status line was removed still says something true until it resets.
        let statusLineReport = ClaudeUsageReader.read(from: paths.claudeUsage)
        let liveReport: UsageReport? = if case .report(let report) = claudeLive { report } else { nil }
        let claudeReport = newest(statusLineReport, liveReport)
        // Claude Code's own answer needs no setup; the status line is only the fallback.
        let claudeSource: AgentUsage.Source = if liveReport != nil { .connected }
            else if claudeLive == .unavailable && statusLineReport == nil { .unavailable }
            else if !claudeConnected { .needsSetup }
            else if claudeReport != nil { .connected }
            else if FileManager.default.fileExists(atPath: paths.claudeStatusLineSeen.path) { .notShared }
            else { .waitingForStatusLine }
        var result = [AgentUsage(agent: .claude, source: claudeSource, report: claudeReport)]
        if codexInstalled {
            result.append(AgentUsage(agent: .codex, source: .connected, report: newest(CodexUsageReader.read(sessions: codexSessions), codexLive)))
        }
        return result
    }

    nonisolated static func newest(_ a: UsageReport?, _ b: UsageReport?) -> UsageReport? {
        [a, b].compactMap { $0 }.max { $0.observedAt < $1.observedAt }
    }

    private func publish(_ next: [AgentUsage]) {
        guard next != usage else { return }
        usage = next
        onChange?(next)
    }
}
