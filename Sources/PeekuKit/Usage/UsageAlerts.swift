import Foundation

/// "Alert me when Claude (or Codex, or either) reaches 90% of a limit." Applies to every window the agent reports.
public struct UsageAlertRule: Codable, Hashable, Identifiable, Sendable {
    public enum Scope: String, Codable, CaseIterable, Sendable {
        case claude, codex, both

        /// "Claude", "Codex", or "Claude and Codex".
        public var title: String {
            switch self {
            case .claude: "Claude"
            case .codex: "Codex"
            case .both: "Claude and Codex"
            }
        }

        public func covers(_ agent: Agent) -> Bool {
            switch self {
            case .claude: agent == .claude
            case .codex: agent == .codex
            case .both: true
            }
        }
    }

    public var id: UUID
    public var scope: Scope
    /// A percentage, 1 to 100.
    public var threshold: Int

    public init(id: UUID = UUID(), scope: Scope, threshold: Int) {
        self.id = id
        self.scope = scope
        self.threshold = threshold
    }

    public static let defaults = [UsageAlertRule(scope: .both, threshold: 90)]
    /// The thresholds the Usage tab offers as chips. Any other one can be typed.
    public static let thresholds = [50, 75, 90, 95]
    public static let validThresholds = 1...100

    /// Rules in the Usage tab's order: Claude, Codex, both, then lowest threshold first.
    public static func sorted(_ rules: [UsageAlertRule]) -> [UsageAlertRule] {
        let order = Scope.allCases
        return rules.sorted { a, b in
            a.scope == b.scope ? a.threshold < b.threshold : order.firstIndex(of: a.scope)! < order.firstIndex(of: b.scope)!
        }
    }
}

/// Turns usage readings into alerts, one for each rate limit window past a rule's threshold.
/// A window alerts once per threshold it crosses: opened at 75%, it alerts again at a 90% rule,
/// and stays quiet after that until a reading shows it reset or back under every threshold.
public struct UsageAlerts: Sendable {
    /// The highest threshold whose alert was opened, by alert id. Saved so a relaunch doesn't repeat them.
    public private(set) var handled: [String: Int]
    /// Each window's current episode: the threshold it crossed, and when.
    private var episodes: [String: (threshold: Int, since: Date)] = [:]

    public init(handled: [String: Int] = [:]) {
        self.handled = handled
    }

    public static func id(_ agent: Agent, _ window: UsageWindow) -> String { "usage:\(agent.rawValue):\(window.id)" }

    /// The alerts to show now.
    public mutating func update(_ usage: [AgentUsage], rules: [UsageAlertRule], now: Date = Date()) -> [PeekuSession] {
        var alerts: [PeekuSession] = []
        var present: Set<String> = []
        for report in usage.compactMap(\.report) {
            let thresholds = rules.filter { $0.scope.covers(report.agent) }.map(\.threshold)
            for window in report.windows {
                let id = Self.id(report.agent, window)
                present.insert(id)
                guard !thresholds.isEmpty else { continue }
                guard let crossed = thresholds.filter({ window.usedPercent >= Double($0) }).max(), !window.hasReset(now: now) else {
                    handled[id] = nil
                    episodes[id] = nil
                    continue
                }
                if let opened = handled[id], opened >= crossed { continue }
                if episodes[id]?.threshold != crossed { episodes[id] = (crossed, report.observedAt) }
                alerts.append(Self.alert(id: id, agent: report.agent, window: window, threshold: crossed,
                                         since: episodes[id]?.since ?? report.observedAt, now: now))
            }
        }
        // A missing reading says nothing about the window, so `handled` keeps it.
        episodes = episodes.filter { present.contains($0.key) }
        return alerts
    }

    /// The user opened this alert.
    public mutating func handle(_ id: String) {
        guard let episode = episodes.removeValue(forKey: id) else { return }
        handled[id] = episode.threshold
    }

    static func alert(id: String, agent: Agent, window: UsageWindow, threshold: Int, since: Date, now: Date) -> PeekuSession {
        let name = window.title.hasSuffix("limit") ? window.title : "\(window.title) limit"
        let used = "\(Int(window.usedPercent.rounded()))% used"
        let resets = window.resetsAt.map { date in
            let sameDay = Calendar.current.isDate(date, inSameDayAs: now)
            return "resets " + (sameDay ? date.formatted(date: .omitted, time: .shortened)
                                        : date.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
        }
        return PeekuSession(id: id, agent: agent, project: name, task: used, host: .other, kind: .usage,
                          quote: [used, "alert at \(threshold)%", resets].compactMap { $0 }.joined(separator: " · "), since: since)
    }
}
