import Foundation

/// One moment worth remembering: an agent needed you, finished, or started a task.
/// History is a log of these, not a metrics view.
public struct HistoryEntry: Codable, Identifiable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case started, permission, question, waiting, error, finished

        init?(_ kind: SessionKind) {
            switch kind {
            case .permission: self = .permission
            case .question: self = .question
            case .waiting: self = .waiting
            case .error: self = .error
            case .finished: self = .finished
            case .idle, .working, .usage: return nil
            }
        }

        /// Needed you: Pip asked for your attention.
        public var neededYou: Bool { self == .permission || self == .question || self == .waiting }
    }

    public var id: String
    public var sessionID: String
    /// `nil` in entries saved before Codex support, meaning Claude Code.
    public var agent: Agent?
    public var project: String
    public var host: HostApp
    public var kind: Kind
    public var at: Date
    /// The command, question, error, summary or task.
    public var detail: String?
    /// When a waiting episode ended. Nil while it's still open, or when Pip wasn't running to see it end.
    public var endedAt: Date?
    public var ended = false
    /// How long a finished run took, from when it started working.
    public var duration: TimeInterval?

    public init(id: String, sessionID: String, agent: Agent? = nil, project: String, host: HostApp, kind: Kind, at: Date,
                detail: String? = nil, endedAt: Date? = nil, ended: Bool = false, duration: TimeInterval? = nil) {
        self.id = id
        self.sessionID = sessionID
        self.agent = agent
        self.project = project
        self.host = host
        self.kind = kind
        self.at = at
        self.detail = detail
        self.endedAt = endedAt
        self.ended = ended
        self.duration = duration
    }

    var isOpenEpisode: Bool { kind != .started && kind != .finished && !ended }

    /// Line two of a history row, e.g. "npm install stripe@17.2.0 · answered after 38s".
    public var summary: String {
        var parts = [detail].compactMap { $0 }
        switch kind {
        case .permission, .question, .waiting:
            if let endedAt { parts.append("answered after \(Durations.short(endedAt.timeIntervalSince(at)))") }
            else if !ended { parts.append("waiting") }
        case .error:
            if let endedAt { parts.append("cleared after \(Durations.short(endedAt.timeIntervalSince(at)))") }
        case .finished:
            if let duration { parts.append(Durations.short(duration)) }
        case .started:
            break
        }
        return parts.joined(separator: " · ")
    }
}

public enum Durations {
    /// "38s", "1m 12s", "4m", "12m", "2h 5m".
    public static func short(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval.rounded()))
        switch seconds {
        case ..<60: return "\(seconds)s"
        case ..<600:
            let rest = seconds % 60
            return rest == 0 ? "\(seconds / 60)m" : "\(seconds / 60)m \(rest)s"
        case ..<3600: return "\(seconds / 60)m"
        default:
            let minutes = (seconds % 3600) / 60
            return minutes == 0 ? "\(seconds / 3600)h" : "\(seconds / 3600)h \(minutes)m"
        }
    }
}
