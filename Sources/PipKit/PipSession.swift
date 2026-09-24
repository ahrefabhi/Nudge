import Foundation

/// The app a Claude Code session runs in. Pip only focuses these; it never types into them.
public enum HostApp: String, Sendable, Hashable, CaseIterable, Codable {
    case iTerm, terminal, vsCode, claude, other

    public var displayName: String {
        switch self {
        case .iTerm: "iTerm"
        case .terminal: "Terminal"
        case .vsCode: "VS Code"
        case .claude: "Claude"
        case .other: "Claude Code"
        }
    }
}

public enum SessionKind: Sendable, Hashable {
    /// Started, with no prompt yet.
    case idle
    case working, permission, question, waiting, error, finished

    public var needsYou: Bool {
        switch self {
        case .permission, .question, .waiting, .error: true
        case .idle, .working, .finished: false
        }
    }
}

/// The coding agent a session belongs to.
public enum Agent: String, Sendable, Hashable, CaseIterable, Codable {
    case claude, codex

    /// For copy like "Claude needs your permission".
    public var name: String { self == .claude ? "Claude" : "Codex" }
    public var productName: String { self == .claude ? "Claude Code" : "Codex" }
}

public struct PipSession: Identifiable, Hashable, Sendable {
    public let id: String
    public var agent: Agent
    public var project: String
    public var branch: String?
    /// What the session is for, e.g. "Upgrading Stripe SDK to v17".
    public var task: String
    /// What it is doing right now, e.g. "Editing session.ts". Working rows prefer it.
    public var activity: String?
    public var host: HostApp
    /// Where inside the host, e.g. "Tab 1" or "Window 1", when known.
    public var location: String?
    public var kind: SessionKind
    /// The command, question, error or summary shown in the context box.
    public var quote: String?
    public var choices: [String]
    /// When the session entered its current kind. Queue ties go to the oldest.
    public var since: Date

    public init(
        id: String, agent: Agent = .claude, project: String, branch: String? = nil, task: String, activity: String? = nil,
        host: HostApp, location: String? = nil, kind: SessionKind, quote: String? = nil, choices: [String] = [], since: Date
    ) {
        self.id = id
        self.agent = agent
        self.project = project
        self.branch = branch
        self.task = task
        self.activity = activity
        self.host = host
        self.location = location
        self.kind = kind
        self.quote = quote
        self.choices = choices
        self.since = since
    }

    public var needsYou: Bool { kind.needsYou }

    /// Identifies one attention episode. Resolving it hides the session until it changes state again.
    public var attentionKey: String { "\(id)|\(kind)|\(since.timeIntervalSinceReferenceDate)" }

    public var hostLabel: String {
        location.map { "\(host.displayName) · \($0)" } ?? host.displayName
    }
}
