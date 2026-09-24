import Foundation
import PipHookSchema

/// What Pip knows about one Claude Code or Codex session, from hook events (and, for Claude
/// Code, its session registry).
public struct ObservedSession: Sendable, Equatable, Codable {
    public enum Phase: Sendable, Equatable, Codable {
        case idle
        case working
        case permission(Permission)
        case question(Question)
        /// Claude reports it is waiting, but no hook said why.
        case waiting(String?)
        case failed(String)
        case finished(summary: String?)

        public var needsUser: Bool {
            switch self {
            case .permission, .question, .waiting, .failed: true
            case .idle, .working, .finished: false
            }
        }

        /// The tool call the user is being asked about, when known.
        var toolUseID: String? {
            switch self {
            case .permission(let permission): permission.toolUseID
            case .question(let question): question.toolUseID
            default: nil
            }
        }
    }

    public struct Permission: Sendable, Equatable, Codable {
        public var toolName: String
        /// The command, file or pattern being approved.
        public var preview: String?
        public var detail: String?
        public var toolUseID: String?
    }

    public struct Question: Sendable, Equatable, Codable {
        public var text: String
        public var choices: [String]
        public var toolUseID: String?
    }

    public let id: String
    public var pid: Int32?
    public var cwd: String
    /// Claude's own short title for the session, from the registry.
    public var title: String?
    /// e.g. "cli" or "claude-vscode".
    public var entrypoint: String?
    public var prompt: String?
    public var activity: String?
    public var phase: Phase = .idle
    /// When `phase` last changed kind.
    public var since: Date
    public var lastEventAt: Date
    public var host = HookRecord.HostHint()
    /// Whether this session is listed in Claude's session registry.
    public var registered = false
    /// `nil` means Claude Code: sessions saved before Codex support have no agent.
    public var agent: Agent?

    public var resolvedAgent: Agent { agent ?? .claude }

    public init(id: String, cwd: String, since: Date) {
        self.id = id
        self.cwd = cwd
        self.since = since
        lastEventAt = since
    }
}

/// Session state on disk, so what Pip learned from hooks survives a restart.
public struct SessionStore: Sendable {
    public let url: URL

    public init(url: URL) { self.url = url }
    public init(paths: PipPaths = .default) { url = paths.root.appending(path: "sessions.json") }

    public func load() -> [ObservedSession] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? Self.decoder.decode([ObservedSession].self, from: data)) ?? []
    }

    public func save(_ sessions: [ObservedSession]) {
        guard let data = try? Self.encoder.encode(sessions.sorted { $0.id < $1.id }) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        try? data.write(to: url, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }()
}
