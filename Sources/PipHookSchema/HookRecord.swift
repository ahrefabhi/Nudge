import Foundation

/// One Claude Code hook event, trimmed to what Pip shows, as the collector writes it to the inbox.
public struct HookRecord: Codable, Sendable, Equatable {
    public static let currentSchema = 1
    public static let maximumBytes = 64 * 1024

    public var schema: Int
    public var id: String
    public var event: String
    /// Milliseconds since 1970, when the collector ran.
    public var observedAt: Int64
    public var sessionID: String
    public var agentID: String?
    public var toolUseID: String?
    public var cwd: String?
    public var prompt: String?
    public var toolName: String?
    public var toolInput: ToolInput?
    public var error: String?
    public var message: String?
    public var notificationType: String?
    public var lastAssistantMessage: String?
    public var host: HostHint?
    /// Set when fields were dropped to fit `maximumBytes`.
    public var truncated: Bool?

    public init(id: String, event: String, observedAt: Int64, sessionID: String) {
        schema = Self.currentSchema
        self.id = id
        self.event = event
        self.observedAt = observedAt
        self.sessionID = sessionID
    }

    public var date: Date { Date(timeIntervalSince1970: TimeInterval(observedAt) / 1000) }

    public struct ToolInput: Codable, Sendable, Equatable {
        public var filePath: String?
        public var pattern: String?
        public var query: String?
        public var description: String?
        /// First 512 characters of a shell command.
        public var command: String?
        public var questions: [Question]?

        public init() {}
    }

    public struct Question: Codable, Sendable, Equatable {
        public var question: String
        public var header: String?
        public var options: [String]
        public var multiSelect: Bool

        public init(question: String, header: String? = nil, options: [String], multiSelect: Bool = false) {
            self.question = question
            self.header = header
            self.options = options
            self.multiSelect = multiSelect
        }
    }

    /// Where the session runs, from the environment Claude Code passes to hooks.
    public struct HostHint: Codable, Sendable, Equatable {
        public var bundleID: String?
        public var termProgram: String?
        /// iTerm's `wNtNpN:GUID`, which names the exact tab and pane.
        public var itermSessionID: String?
        public var parentPID: Int32?

        public init(bundleID: String? = nil, termProgram: String? = nil, itermSessionID: String? = nil, parentPID: Int32? = nil) {
            self.bundleID = bundleID
            self.termProgram = termProgram
            self.itermSessionID = itermSessionID
            self.parentPID = parentPID
        }
    }

    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}

/// Pip's own data folder. `PIP_HOME` overrides it, for tests and development.
public struct PipPaths: Sendable, Equatable {
    public var root: URL

    public init(root: URL) { self.root = root }

    public static var `default`: PipPaths {
        if let custom = ProcessInfo.processInfo.environment["PIP_HOME"], !custom.isEmpty {
            return PipPaths(root: URL(filePath: custom, directoryHint: .isDirectory))
        }
        let support = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support/Pip", directoryHint: .isDirectory)
        return PipPaths(root: support)
    }

    public var inbox: URL { root.appending(path: "inbox", directoryHint: .isDirectory) }
    public var collector: URL { root.appending(path: "bin/pip-hook") }
}
