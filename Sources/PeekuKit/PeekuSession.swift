import Foundation

/// The app a Claude Code session runs in. Peeku only focuses these; it never types into them.
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
    /// Not a session: one of the agent's rate limits has passed the user's alert threshold.
    case usage

    public var needsYou: Bool {
        switch self {
        case .permission, .question, .waiting, .error, .usage: true
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

public struct PeekuSession: Identifiable, Hashable, Sendable {
    public let id: String
    public var agent: Agent
    public var project: String
    public var branch: String?
    /// What the session is for, e.g. "Upgrading Stripe SDK to v17".
    public var task: String
    /// What it is doing right now, e.g. "Editing session.ts". Working rows prefer it.
    public var activity: String?
    public var host: HostApp
    /// The app's own name when `host` is `.other`, e.g. "Warp" or "Ghostty".
    public var hostAppName: String?
    /// That app's bundle id, for hiding it.
    public var hostBundleID: String?
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
        host: HostApp, hostAppName: String? = nil, hostBundleID: String? = nil, location: String? = nil, kind: SessionKind, quote: String? = nil, choices: [String] = [], since: Date
    ) {
        self.id = id
        self.agent = agent
        self.project = project
        self.branch = branch
        self.task = task
        self.activity = activity
        self.host = host
        self.hostAppName = hostAppName
        self.hostBundleID = hostBundleID
        self.location = location
        self.kind = kind
        self.quote = quote
        self.choices = choices
        self.since = since
    }

    public var needsYou: Bool { kind.needsYou }

    /// Identifies one attention episode. Resolving it hides the session until it changes state again.
    public var attentionKey: String { "\(id)|\(kind)|\(since.timeIntervalSinceReferenceDate)" }

    /// Where it's running, e.g. "iTerm" or "Warp". A usage alert belongs to the agent, not an app,
    /// and so does a session in an app Peeku couldn't identify.
    public var hostName: String {
        if kind == .usage { return agent.productName }
        if host == .other { return hostAppName ?? agent.productName }
        return host.displayName
    }

    public var hostLabel: String {
        location.map { "\(hostName) · \($0)" } ?? hostName
    }
}
